#!/bin/bash

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
NC='\033[0m' # No Color

# Logging functions
log() {
    echo -e "${GREEN}[INFO]${NC} $1"
}

warn() {
    echo -e "${YELLOW}[WARN]${NC} $1"
}

error() {
    echo -e "${RED}[ERROR]${NC} $1"
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

execute_remote() {
    local command="$1"
    if ! ssh "${CONTROL_PLANE_NODES[0]}" "sudo $command"; then
        error "Failed to execute command on remote host: $command"
        return 1
    fi
}

# Function to check for resources in Terminating state
check_terminating() {
    local terminating_resources=$(execute_remote "kubectl get all --all-namespaces -o json" | jq '.items[] | select(.metadata.deletionTimestamp != null) | "\(.kind) \(.metadata.name) in namespace \(.metadata.namespace)"')
    if [ ! -z "$terminating_resources" ]; then
        error "Found resources stuck in Terminating state:"
        echo "$terminating_resources"
        return 1
    fi
    return 0
}

# Function to force delete terminating resources
force_delete_terminating() {
    warn "Attempting to force delete stuck resources..."
    
    # Get all resources in all namespaces
    for ns in $(execute_remote "kubectl get ns -o name"); do
        ns=${ns#namespace/}
        
        # Get all resources in terminating state and force delete them
        execute_remote "kubectl get all -n $ns -o json" | jq -r '.items[] | select(.metadata.deletionTimestamp != null) | "\(.kind)/\(.metadata.name)"' | while read resource; do
            if [ ! -z "$resource" ]; then
                log "Force deleting $resource in namespace $ns"
                execute_remote "kubectl delete $resource -n $ns --force --grace-period=0"
            fi
        done
    done
}

# Main script
log "Starting Kubernetes cluster cleanup..."

# Read cluster configuration
parse_cluster_file

error "WARNING: This will delete all resources except nodes and critical system components"
read -p "Are you sure you want to continue? (y/n) " -n 1 -r
echo
if [[ ! $REPLY =~ ^[Yy]$ ]]
then
    warn "Cleanup cancelled."
    exit 1
fi

# Before cleanup diagnostics
log "Current ingress-related resources:"
execute_remote "kubectl get validatingwebhookconfigurations | grep ingress || true"
execute_remote "kubectl get namespace ingress-nginx || true"
execute_remote "kubectl get pods -A | grep ingress || true"

# Ingress-specific cleanup
log "Cleaning up Ingress resources..."

# Force delete ingress-nginx namespace
execute_remote "kubectl delete namespace ingress-nginx --force --grace-period=0 || true"

# Remove any helm releases
execute_remote "helm list -n ingress-nginx -q | xargs -r helm uninstall -n ingress-nginx || true"

# Delete ingress classes
execute_remote "kubectl delete ingressclass nginx || true"

# Delete all webhook configurations related to ingress-nginx
execute_remote "kubectl get validatingwebhookconfigurations -o name | grep ingress-nginx | xargs -r kubectl delete || true"
execute_remote "kubectl get mutatingwebhookconfigurations -o name | grep ingress-nginx | xargs -r kubectl delete || true"

# Delete any remaining ingress-related resources
execute_remote "kubectl delete -A ValidatingWebhookConfiguration,MutatingWebhookConfiguration -l app.kubernetes.io/name=ingress-nginx || true"
execute_remote "kubectl delete -A ValidatingWebhookConfiguration,MutatingWebhookConfiguration -l app.kubernetes.io/part-of=ingress-nginx || true"

# Clean up any possible leftover resources
execute_remote "for CRD in \$(kubectl get crd -o name | grep -i ingress); do kubectl delete \$CRD --force --grace-period=0 || true; done"

# Delete any services with ingress-nginx label
execute_remote "kubectl delete services -l app.kubernetes.io/name=ingress-nginx -A --force --grace-period=0 || true"

# Delete any pods with ingress-nginx label
execute_remote "kubectl delete pods -l app.kubernetes.io/name=ingress-nginx -A --force --grace-period=0 || true"

# Add a longer wait for ingress-nginx namespace deletion
log "Waiting for ingress-nginx namespace deletion..."
execute_remote "kubectl wait --for=delete namespace/ingress-nginx --timeout=120s || true"

# Force remove finalizers if namespace is stuck
execute_remote "kubectl get namespace ingress-nginx -o json | jq '.spec.finalizers = []' | kubectl replace --raw \"/api/v1/namespaces/ingress-nginx/finalize\" -f - || true"

# Additional cleanup for any numbered ingress-nginx resources
execute_remote "for i in {1..5}; do kubectl delete validatingwebhookconfiguration ingress-nginx-\$i-admission 2>/dev/null || true; done"

# Wait before continuing
warn "Waiting 10 seconds before continuing with general cleanup..."
sleep 10

# After cleanup verification
log "Verifying ingress cleanup:"
execute_remote "kubectl get validatingwebhookconfigurations | grep ingress || true"
execute_remote "kubectl get namespace ingress-nginx || true"
execute_remote "kubectl get pods -A | grep ingress || true"

# Main cleanup process
log "Deleting all resources in all namespaces..."
execute_remote "kubectl delete all --all --all-namespaces"

log "Deleting non-system namespaces..."
execute_remote "kubectl get namespaces -o name | grep -v -E '^namespace/(kube-system|kube-public|kube-node-lease|default)$' | xargs -r kubectl delete"

log "Deleting cluster-wide resources..."
execute_remote "kubectl delete clusterroles,clusterrolebindings --all"

log "Deleting ConfigMaps (except kube-system)..."
execute_remote "kubectl delete configmaps --all --all-namespaces --field-selector metadata.namespace!=kube-system"

log "Deleting Secrets (except kube-system)..."
execute_remote "kubectl delete secrets --all --all-namespaces --field-selector metadata.namespace!=kube-system"

log "Deleting PersistentVolumes..."
execute_remote "kubectl delete pv --all"

log "Deleting PersistentVolumeClaims..."
execute_remote "kubectl delete pvc --all --all-namespaces"

log "Deleting StorageClasses..."
execute_remote "kubectl delete storageclasses --all"

log "Deleting CustomResourceDefinitions..."
execute_remote "kubectl delete crd --all"

# Wait a bit for deletions to process
warn "Waiting 30 seconds for deletions to process..."
sleep 30

# Check for terminating resources
log "Checking for resources stuck in Terminating state..."
if ! check_terminating; then
    error "Found resources in Terminating state. Attempting force deletion..."
    force_delete_terminating
    
    # Wait and check again
    warn "Waiting 10 seconds and performing final check..."
    sleep 10
    if ! check_terminating; then
        error "Some resources are still stuck. You may need to handle them manually."
        exit 1
    fi
fi

log "Cleanup completed successfully!"