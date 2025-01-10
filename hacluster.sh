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

# Function to display the script description and usage
show_description() {
    echo
    echo "================================================================================"
    echo "Highly Available (HA) Lightweight Kubernetes (K3s) Cluster Deployment Script"
    echo "================================================================================"
    echo
    echo "This script automates the deployment of a Highly Available (HA) lightweight Kubernetes (K3s) cluster"
    echo "connected via Tailscale."
    echo
    echo "Prerequisites:"
    echo "1. A local machine running Ubuntu 24.04 with the following tools installed:"
    echo "   - kubectl"
    echo "   - helm"
    echo "   - curl"
    echo "   - ssh"
    echo "   - jq (optional, for JSON parsing)"
    echo
    echo "  Note: The prerequisites will be installed if they are not present on the local machine"
    echo
    echo "2. A file named 'ha_cluster.txt' in the same directory as this script, containing:"
    echo "   - Tailscale IPs and usernames of the nodes, divided into control plane and worker nodes."
    echo "   - Example 'ha_cluster.txt' file:"
    echo ""
    echo "     control plane nodes:"
    echo "     node1@100.121.222.20"
    echo "     node2@100.112.102.15"
    echo "     node3@100.97.250.102"
    echo ""
    echo "     worker nodes:"
    echo "     node4@100.116.163.44"
    echo "     node5@100.66.77.13"
    echo "     node6@100.67.182.33"
    echo ""
    echo "3. Passwordless SSH access to all nodes using an SSH key."
    echo
    echo "4. The cluster nodes should all be set with passwordless sudo."
    echo
    echo "5. Tailscale installed and configured on all nodes."
    echo
    echo "Usage:"
    echo "1. Modify the ha_cluster_template.txt with the nodes' info and rename it to ha_cluster.txt."
    echo "2. Execute the script:"
    echo "   $ bash hacluster.sh"
    echo
    echo "License: Apache 2.0"
    echo "Repo:    https://github.com/mik-tf/k3scluster"
    echo
    echo "================================================================================"
    echo ""
    while true; do
        read -p "Do you want to proceed? (y/n): " USER_INPUT
        case $USER_INPUT in
            [Yy]* )
                log "Starting the script..."
                break
                ;;
            [Nn]* )
                log "Exiting the script. Goodbye!"
                exit 0
                ;;
            * )
                warn "Please answer 'y' to proceed or 'n' to exit."
                ;;
        esac
    done
}

# Function to check and install prerequisites
check_prerequisites() {
    log "Checking prerequisites on the local machine..."

    # List of required tools
    REQUIRED_TOOLS=("kubectl" "helm" "curl" "ssh" "jq")

    # Check if each tool is installed
    for TOOL in "${REQUIRED_TOOLS[@]}"; do
        if ! command -v $TOOL &> /dev/null; then
            warn "$TOOL is not installed. Installing now..."
            case $TOOL in
                "kubectl")
                    sudo apt-get update
                    sudo apt-get install -y apt-transport-https ca-certificates curl
                    sudo curl -fsSLo /usr/share/keyrings/kubernetes-archive-keyring.gpg https://packages.cloud.google.com/apt/doc/apt-key.gpg
                    echo "deb [signed-by=/usr/share/keyrings/kubernetes-archive-keyring.gpg] https://apt.kubernetes.io/ kubernetes-xenial main" | sudo tee /etc/apt/sources.list.d/kubernetes.list
                    sudo apt-get update
                    sudo apt-get install -y kubectl
                    ;;
                "helm")
                    curl -fsSL -o get_helm.sh https://raw.githubusercontent.com/helm/helm/main/scripts/get-helm-3
                    chmod 700 get_helm.sh
                    ./get_helm.sh
                    rm ./get_helm.sh
                    ;;
                "curl" | "ssh" | "jq")
                    sudo apt-get update
                    sudo apt-get install -y $TOOL
                    ;;
                *)
                    error "Unsupported tool: $TOOL. Please install it manually."
                    exit 1
                    ;;
            esac
        else
            log "$TOOL is already installed."
        fi
    done

    log "All prerequisites are installed and ready."
}

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

# Main script execution

# Step 1: Show script description
show_description

# Step 2: Check prerequisites
log "Step 1: Checking prerequisites on the local machine..."
check_prerequisites

# Step 3: Parse the cluster file
log "Step 2: Parsing the ha_cluster.txt file..."
parse_cluster_file

# Step 4: Verify Tailscale Connectivity
log "Step 3: Verifying Tailscale connectivity..."
for NODE in "${CONTROL_PLANE_NODES[@]}" "${WORKER_NODES[@]}"; do
    USER=$(echo $NODE | cut -d'@' -f1)
    IP=$(echo $NODE | cut -d'@' -f2)
    log "Checking connectivity to $USER ($IP)..."
    if ! ssh -i ~/.ssh/id_ed25519 $USER@$IP "echo 'Connected to $USER'" &> /dev/null; then
        error "Failed to connect to $USER@$IP"
        exit 1
    fi
done

# Step 5: Install Kubernetes (k3s)
log "Step 4: Installing Kubernetes (k3s)..."

# Install k3s on the first control plane node
FIRST_CP_USER=$(echo ${CONTROL_PLANE_NODES[0]} | cut -d'@' -f1)
FIRST_CP_IP=$(echo ${CONTROL_PLANE_NODES[0]} | cut -d'@' -f2)
log "Installing k3s on first control plane node $FIRST_CP_USER ($FIRST_CP_IP)..."
ssh -i ~/.ssh/id_ed25519 $FIRST_CP_USER@$FIRST_CP_IP "curl -sfL https://get.k3s.io | INSTALL_K3S_EXEC=\"--cluster-init --tls-san $FIRST_CP_IP\" sh -"

# Retrieve the token from the first control plane node
TOKEN=$(ssh -i ~/.ssh/id_ed25519 $FIRST_CP_USER@$FIRST_CP_IP "sudo cat /var/lib/rancher/k3s/server/node-token")

# Install k3s on additional control plane nodes
for NODE in "${CONTROL_PLANE_NODES[@]:1}"; do
    USER=$(echo $NODE | cut -d'@' -f1)
    IP=$(echo $NODE | cut -d'@' -f2)
    log "Installing k3s on additional control plane node $USER ($IP)..."
    ssh -i ~/.ssh/id_ed25519 $USER@$IP "curl -sfL https://get.k3s.io | INSTALL_K3S_EXEC=\"--server https://$FIRST_CP_IP:6443 --token $TOKEN --tls-san $IP\" sh -"
done

# Install k3s on worker nodes
for NODE in "${WORKER_NODES[@]}"; do
    USER=$(echo $NODE | cut -d'@' -f1)
    IP=$(echo $NODE | cut -d'@' -f2)
    log "Installing k3s on worker node $USER ($IP)..."
    ssh -i ~/.ssh/id_ed25519 $USER@$IP "curl -sfL https://get.k3s.io | K3S_URL=https://$FIRST_CP_IP:6443 K3S_TOKEN=$TOKEN sh -"
done

# Verify the cluster
log "Verifying the cluster..."

# Calculate timeout based on number of nodes (30 seconds per node)
TOTAL_NODES=$((${#CONTROL_PLANE_NODES[@]} + ${#WORKER_NODES[@]}))
MAX_ATTEMPTS=$((TOTAL_NODES * 3)) # 30 seconds per node (3 attempts * 10 seconds)

# Wait for nodes to be ready
log "Waiting for all nodes to be ready..."
for ((i=1; i<=MAX_ATTEMPTS; i++)); do
    READY_NODES=$(ssh -i ~/.ssh/id_ed25519 $FIRST_CP_USER@$FIRST_CP_IP "sudo kubectl get nodes | grep -c 'Ready'")
    
    if [ "$READY_NODES" -eq "$TOTAL_NODES" ]; then
        log "All nodes are ready!"
        break
    fi
    
    if [ "$i" -eq "$MAX_ATTEMPTS" ]; then
        error "Timeout waiting for nodes to be ready. Only $READY_NODES/$TOTAL_NODES nodes are ready."
        exit 1
    fi
    
    warn "Waiting for nodes to be ready ($READY_NODES/$TOTAL_NODES)... Attempt $i/$MAX_ATTEMPTS"
    sleep 10
done

# Label worker nodes
log "Labeling worker nodes..."
# First, get the actual node names from the cluster
NODE_NAMES=$(ssh -i ~/.ssh/id_ed25519 $FIRST_CP_USER@$FIRST_CP_IP "sudo kubectl get nodes -o jsonpath='{.items[*].metadata.name}'")

# Convert string to array
readarray -t NODE_ARRAY <<< "$(echo $NODE_NAMES | tr ' ' '\n')"

# Label worker nodes (assuming the last N nodes are workers, where N is the number of worker nodes)
WORKER_COUNT=${#WORKER_NODES[@]}
START_INDEX=$((${#NODE_ARRAY[@]} - WORKER_COUNT))

for ((i=START_INDEX; i<${#NODE_ARRAY[@]}; i++)); do
    NODE_NAME="${NODE_ARRAY[$i]}"
    log "Adding worker role label to node $NODE_NAME..."
    ssh -i ~/.ssh/id_ed25519 $FIRST_CP_USER@$FIRST_CP_IP "sudo kubectl label node $NODE_NAME node-role.kubernetes.io/worker=true --overwrite" || {
        warn "Failed to label node $NODE_NAME, but continuing..."
    }
done

# Show cluster status
log "Cluster Status:"
echo "---------------"
ssh -i ~/.ssh/id_ed25519 $FIRST_CP_USER@$FIRST_CP_IP "sudo kubectl get nodes -o wide"

log "Cluster setup completed successfully!"