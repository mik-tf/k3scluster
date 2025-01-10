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

# Function to clean up k3s installation
cleanup_k3s() {
    NODE=$1
    USER=$(echo $NODE | cut -d'@' -f1)
    IP=$(echo $NODE | cut -d'@' -f2)
    
    log "Cleaning up k3s on $USER ($IP)..."
    
    # Stop and uninstall k3s
    if ! ssh -i ~/.ssh/id_ed25519 $USER@$IP "sudo systemctl stop k3s k3s-agent"; then
        warn "Failed to stop k3s services on $USER@$IP"
    fi
    
    if ! ssh -i ~/.ssh/id_ed25519 $USER@$IP "/usr/local/bin/k3s-uninstall.sh"; then
        warn "Failed to run k3s-uninstall.sh on $USER@$IP"
    fi
    
    if ! ssh -i ~/.ssh/id_ed25519 $USER@$IP "/usr/local/bin/k3s-agent-uninstall.sh"; then
        warn "Failed to run k3s-agent-uninstall.sh on $USER@$IP"
    fi
    
    # Clean up network configurations
    log "Cleaning up network configurations on $USER@$IP..."
    ssh -i ~/.ssh/id_ed25519 $USER@$IP "sudo ip link delete cni0" || warn "Failed to delete cni0 interface"
    ssh -i ~/.ssh/id_ed25519 $USER@$IP "sudo ip link delete flannel.1" || warn "Failed to delete flannel.1 interface"
    ssh -i ~/.ssh/id_ed25519 $USER@$IP "sudo iptables -F" || warn "Failed to flush iptables"
    ssh -i ~/.ssh/id_ed25519 $USER@$IP "sudo iptables -t nat -F" || warn "Failed to flush nat tables"
    
    # Clean up residual files and directories
    log "Removing k3s directories on $USER@$IP..."
    ssh -i ~/.ssh/id_ed25519 $USER@$IP "sudo rm -rf /var/lib/rancher/k3s" || warn "Failed to remove /var/lib/rancher/k3s"
    ssh -i ~/.ssh/id_ed25519 $USER@$IP "sudo rm -rf /etc/rancher/k3s" || warn "Failed to remove /etc/rancher/k3s"
}

# Parse the cluster file
log "Parsing cluster configuration file..."
parse_cluster_file

# Clean up control plane nodes
log "Cleaning up control plane nodes..."
for NODE in "${CONTROL_PLANE_NODES[@]}"; do
    cleanup_k3s $NODE
    sudo systemctl daemon-reload
done

# Clean up worker nodes
log "Cleaning up worker nodes..."
for NODE in "${WORKER_NODES[@]}"; do
    cleanup_k3s $NODE
    sudo systemctl daemon-reload
done

# Clea up Kubectl files
log "Cleaning up local Kubectl files..."
rm ./kubeconfig

log "Cleanup complete. You can now run the main script."