#!/bin/bash
set -e

K3D_CLUSTER_NAME="wiki-cluster"

# Avoid DinD TLS cert generation/verification issues (e.g. clock skew).
export DOCKER_TLS_CERTDIR=""

mkdir -p "${HOME:-/root}/.kube"
export KUBECONFIG="${HOME:-/root}/.kube/config"

echo "Starting Docker daemon..."
dockerd \
    --host=unix:///var/run/docker.sock \
    >/var/log/dockerd.log 2>&1 &

# Wait for Docker to be ready
echo "Waiting for Docker to be ready..."
timeout=60
until docker info >/dev/null 2>&1; do
    timeout=$((timeout - 1))
    if [ $timeout -le 0 ]; then
        echo "Docker daemon failed to start"
        exit 1
    fi
    sleep 1
done
echo "Docker is ready"

# Build the wiki-service Docker image
echo "Building wiki-service Docker image..."
cd /app/wiki-service
docker build -t wiki-service:latest .
cd /app

# Create k3d cluster (keep LB enabled for port mappings)
echo "Creating k3d cluster..."
if k3d cluster list | awk 'NR>1{print $1}' | grep -qx "${K3D_CLUSTER_NAME}"; then
    echo "Existing k3d cluster '${K3D_CLUSTER_NAME}' found; deleting it..."
    k3d cluster delete "${K3D_CLUSTER_NAME}" || true
fi

k3d cluster create --config k3d-config.yaml --api-port 127.0.0.1:6443 --wait

echo "Configuring kubectl context..."
k3d kubeconfig merge "${K3D_CLUSTER_NAME}" --kubeconfig-switch-context >/dev/null

# Import the Docker image into k3d
echo "Importing wiki-service image into k3d..."
k3d image import wiki-service:latest -c "${K3D_CLUSTER_NAME}"

# Install nginx ingress controller (NodePort on 30080)
echo "Installing nginx ingress controller..."
helm repo add ingress-nginx https://kubernetes.github.io/ingress-nginx >/dev/null 2>&1 || true
helm repo update >/dev/null 2>&1
helm upgrade --install ingress-nginx ingress-nginx/ingress-nginx \
    --namespace ingress-nginx --create-namespace \
    --set controller.service.type=NodePort \
    --set controller.service.nodePorts.http=30080 \
    --set controller.service.nodePorts.https=30443 \
    --wait --timeout=5m

# Update Helm values to use the local image
echo "Deploying Helm chart..."
helm upgrade --install wiki ./wiki-chart \
    --set fastapi.image_name=wiki-service:latest \
    --wait --timeout=5m

# Wait for all pods to be ready
echo "Waiting for all pods to be ready..."
kubectl wait --for=condition=ready pod --all --timeout=120s

echo "Running smoke tests..."
if ! (cd /app/wiki-service && BASE_URL=http://localhost:8080 bash ./test_api.sh); then
    echo "Smoke tests failed. Dumping diagnostics..." >&2
    kubectl get pods -A >&2 || true
    kubectl describe ingress wiki-ingress >&2 || true
    exit 1
fi

echo ""
echo "========================================="
echo "Deployment complete!"
echo "========================================="
echo "Available endpoints:"
echo "  - http://localhost:8080/users"
echo "  - http://localhost:8080/posts"
echo "  - http://localhost:8080/metrics"
echo "  - http://localhost:8080/grafana/d/creation-dashboard-678/creation"
echo ""
echo "Grafana credentials: admin/admin"
echo "========================================="
echo ""

# Keep container running and show logs
kubectl get pods
echo ""
echo "Container is running. Press Ctrl+C to stop."
tail -f /dev/null
