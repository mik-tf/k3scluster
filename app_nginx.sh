#!/bin/bash

# Logging functions with colors
log() {
    echo -e "\033[1;32m[INFO]\033[0m $1"  # Green
}

warn() {
    echo -e "\033[1;33m[WARN]\033[0m $1"  # Yellow
}

error() {
    echo -e "\033[1;31m[ERROR]\033[0m $1" >&2  # Red
}

# Function to parse the cluster file
parse_cluster_file() {
    CONTROL_PLANE_NODES=()
    WORKER_NODES=()
    MODE=""

    # Check if file exists
    if [[ ! -f ha_cluster.txt ]]; then
        error "ha_cluster.txt file not found!"
        exit 1
    fi

    # Read the file line by line
    while IFS= read -r line || [[ -n "$line" ]]; do
        # Trim leading/trailing whitespace
        line=$(echo "$line" | xargs)

        # Skip empty lines and comments
        if [[ -z "$line" || "$line" == "#"* ]]; then
            continue
        fi

        # Check for section headers
        if [[ "$line" == "control plane nodes:" ]]; then
            MODE="control"
        elif [[ "$line" == "worker nodes:" ]]; then
            MODE="worker"
        elif [[ "$line" =~ ^([^@]+)@([0-9]+\.[0-9]+\.[0-9]+\.[0-9]+)$ ]]; then
            USER=${BASH_REMATCH[1]}
            IP=${BASH_REMATCH[2]}
            if [[ "$MODE" == "control" ]]; then
                CONTROL_PLANE_NODES+=("$USER@$IP")
            elif [[ "$MODE" == "worker" ]]; then
                WORKER_NODES+=("$USER@$IP")
            else
                warn "Node '$USER@$IP' ignored because it is not in a valid section."
            fi
        else
            warn "Invalid line format: '$line'"
        fi
    done < ha_cluster.txt
}

get_magicdns_domain() {
    log "Please enter your Tailscale MagicDNS domain (e.g., tailscale.ts.net):"
    read -p "> " MAGIC_DNS_DOMAIN
    
    # Validate the domain format
    if [[ ! $MAGIC_DNS_DOMAIN =~ ^[a-zA-Z0-9]+\.ts\.net$ ]]; then
        error "Invalid domain format. It should be something like 'tailscale.ts.net'"
        exit 1
    fi
}

# Get MagicDNS domain from user
get_magicdns_domain

# Main script execution
log "Starting NGINX cluster deployment..."

# Parse the cluster file
log "Parsing the ha_cluster.txt file..."
parse_cluster_file

# Get the first control plane node details for kubectl commands
FIRST_CP_USER=$(echo ${CONTROL_PLANE_NODES[0]} | cut -d'@' -f1)
FIRST_CP_IP=$(echo ${CONTROL_PLANE_NODES[0]} | cut -d'@' -f2)

# Deploy NGINX
log "Deploying NGINX application..."
cat <<EOF | ssh -i ~/.ssh/id_ed25519 $FIRST_CP_USER@$FIRST_CP_IP "sudo kubectl apply -f -"
apiVersion: apps/v1
kind: Deployment
metadata:
  name: nginx
spec:
  replicas: 3
  selector:
    matchLabels:
      app: nginx
  template:
    metadata:
      labels:
        app: nginx
    spec:
      containers:
      - name: nginx
        image: nginx:latest
        ports:
        - containerPort: 80
        resources:
          requests:
            cpu: "100m"
            memory: "128Mi"
          limits:
            cpu: "500m"
            memory: "512Mi"
EOF

# Create LoadBalancer Service
TAILSCALE_IPS=()
for NODE in "${WORKER_NODES[@]}"; do
    IP=$(echo $NODE | cut -d'@' -f2)
    TAILSCALE_IPS+=("$IP")
done

log "Creating LoadBalancer service..."
cat <<EOF | ssh -i ~/.ssh/id_ed25519 $FIRST_CP_USER@$FIRST_CP_IP "sudo kubectl apply -f -"
apiVersion: v1
kind: Service
metadata:
  name: nginx-service
spec:
  selector:
    app: nginx
  ports:
  - protocol: TCP
    port: 80
    targetPort: 80
  type: LoadBalancer
  externalIPs:
$(for ip in "${TAILSCALE_IPS[@]}"; do echo "    - $ip"; done)
EOF

# Install and configure Ingress Controllers
log "Setting up kubeconfig for Helm..."
ssh -i ~/.ssh/id_ed25519 $FIRST_CP_USER@$FIRST_CP_IP "sudo cat /etc/rancher/k3s/k3s.yaml" > kubeconfig
sed -i "s/127.0.0.1/$FIRST_CP_IP/" kubeconfig

log "Installing Helm and Ingress Controllers..."
ssh -i ~/.ssh/id_ed25519 $FIRST_CP_USER@$FIRST_CP_IP <<'EOF'
    # Install Helm
    curl https://raw.githubusercontent.com/helm/helm/main/scripts/get-helm-3 | sudo bash
    
    # Add and update Helm repo
    sudo helm repo add ingress-nginx https://kubernetes.github.io/ingress-nginx
    sudo helm repo update
    
    # Create a temporary directory for the kubeconfig
    sudo mkdir -p /root/.kube
    sudo cp /etc/rancher/k3s/k3s.yaml /root/.kube/config
EOF

# Create ingress-nginx namespace
log "Creating ingress-nginx namespace..."
ssh -i ~/.ssh/id_ed25519 $FIRST_CP_USER@$FIRST_CP_IP "sudo kubectl create namespace ingress-nginx || true"

# Install primary Ingress Controller
log "Installing primary Ingress Controller..."
if ! ssh -i ~/.ssh/id_ed25519 $FIRST_CP_USER@$FIRST_CP_IP "sudo KUBECONFIG=/etc/rancher/k3s/k3s.yaml helm install ingress-nginx ingress-nginx/ingress-nginx \
    --namespace ingress-nginx \
    --set controller.nodeSelector.\"kubernetes\\.io/hostname\"=\"$(echo ${WORKER_NODES[0]} | cut -d'@' -f1)\" \
    --set controller.service.type=LoadBalancer \
    --set controller.service.externalTrafficPolicy=Local"; then
    error "Failed to install primary Ingress Controller"
    exit 1
fi

# Wait for the first installation to complete
log "Waiting for primary Ingress Controller to be ready..."
sleep 30

# Install additional Ingress Controllers on other worker nodes
for i in $(seq 1 $((${#WORKER_NODES[@]}-1))); do
    NODE=${WORKER_NODES[$i]}
    USER=$(echo $NODE | cut -d'@' -f1)
    IP=$(echo $NODE | cut -d'@' -f2)
    log "Installing Ingress Controller on $USER ($IP)..."
    
    if ! ssh -i ~/.ssh/id_ed25519 $FIRST_CP_USER@$FIRST_CP_IP "sudo KUBECONFIG=/etc/rancher/k3s/k3s.yaml helm install ingress-nginx-$i ingress-nginx/ingress-nginx \
        --namespace ingress-nginx \
        --set controller.nodeSelector.\"kubernetes\\.io/hostname\"=\"$USER\" \
        --set controller.service.type=LoadBalancer \
        --set controller.service.externalTrafficPolicy=Local \
        --set controller.ingressClassResource.name=nginx-$i \
        --set controller.ingressClass=nginx-$i"; then
        warn "Failed to install Ingress Controller on $USER, continuing with next node..."
        continue
    fi
    
    log "Waiting for Ingress Controller on $USER to be ready..."
    sleep 20
done

# Verify the installations
log "Verifying Ingress Controller installations..."
ssh -i ~/.ssh/id_ed25519 $FIRST_CP_USER@$FIRST_CP_IP "sudo kubectl get pods -n ingress-nginx"
ssh -i ~/.ssh/id_ed25519 $FIRST_CP_USER@$FIRST_CP_IP "sudo kubectl get services -n ingress-nginx"
ssh -i ~/.ssh/id_ed25519 $FIRST_CP_USER@$FIRST_CP_IP "sudo kubectl get ingressclass"

# Wait for deployments to be ready
log "Waiting for all deployments to be ready..."
sleep 30

# Verify deployments
log "Verifying all deployments..."
ssh -i ~/.ssh/id_ed25519 $FIRST_CP_USER@$FIRST_CP_IP "sudo kubectl get pods -A"
ssh -i ~/.ssh/id_ed25519 $FIRST_CP_USER@$FIRST_CP_IP "sudo kubectl get services -A"

# Create arrays to store URLs
declare -a URLS=()

# Print access information and collect URLs
log "NGINX service can be accessed at:"
for NODE in "${WORKER_NODES[@]}"; do
    USER=$(echo $NODE | cut -d'@' -f1)
    IP=$(echo $NODE | cut -d'@' -f2)
    
    # Get the machine name from tailscale status
    MACHINE_NAME=$(ssh -i ~/.ssh/id_ed25519 $USER@$IP "tailscale status --json" | jq -r '.Self.HostName')
    
    # Add URLs to array
    URLS+=("http://$IP")
    URLS+=("http://${MACHINE_NAME}.${MAGIC_DNS_DOMAIN}")
    
    # Also log the URLs
    log "http://$IP"
    log "http://${MACHINE_NAME}.${MAGIC_DNS_DOMAIN}"
done

log "NGINX cluster deployment completed successfully! 🚀"

# Test URL accessibility
log "Testing URL accessibility..."
printf "\n%-45s | %-7s | %-7s | %s\n" "URL" "STATUS" "CODE" "LATENCY"
printf "%s\n" "$(printf '=%.0s' {1..80})"

# Test each URL
for url in "${URLS[@]}"; do
    response=$(curl -o /dev/null -s -w "%{http_code} %{time_total}" "$url")
    
    http_code=$(echo $response | cut -d' ' -f1)
    latency=$(echo $response | cut -d' ' -f2)
    
    # Determine status based on HTTP code
    if [ "$http_code" -eq 200 ]; then
        status="✅ OK"
    else
        status="❌ FAIL"
    fi
    
    # Print table row
    printf "%-45s | %-7s | %-7s | %.3fs\n" "$url" "$status" "$http_code" "$latency"
done