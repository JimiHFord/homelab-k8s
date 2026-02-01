#!/bin/bash
set -e

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_DIR="$(dirname "$SCRIPT_DIR")"
NAMESPACE="forgejo"

echo "🔧 Deploying Forgejo to Kubernetes..."

# Check prerequisites
command -v kubectl >/dev/null 2>&1 || { echo "❌ kubectl not found"; exit 1; }
command -v helm >/dev/null 2>&1 || { echo "❌ helm not found"; exit 1; }

# Check cluster is reachable
kubectl cluster-info >/dev/null 2>&1 || { echo "❌ Cannot connect to cluster"; exit 1; }

# Create namespace
kubectl create namespace "$NAMESPACE" 2>/dev/null || true

# Generate admin password if secret doesn't exist
if ! kubectl get secret forgejo-admin-secret -n "$NAMESPACE" >/dev/null 2>&1; then
    echo "🔐 Creating admin secret..."
    ADMIN_PASSWORD=$(openssl rand -base64 16 | tr -d '=+/')
    kubectl create secret generic forgejo-admin-secret \
        --namespace "$NAMESPACE" \
        --from-literal=username=admin \
        --from-literal=password="$ADMIN_PASSWORD"
    echo "📝 Admin credentials:"
    echo "   Username: admin"
    echo "   Password: $ADMIN_PASSWORD"
    echo ""
    echo "⚠️  Save this password! It won't be shown again."
    echo ""
fi

# Add Gitea Helm repo (compatible with Forgejo)
helm repo add gitea https://dl.gitea.com/charts/ 2>/dev/null || true
helm repo update

# Deploy/upgrade Forgejo (using Gitea chart with Forgejo image)
echo "📦 Installing Forgejo..."
helm upgrade --install forgejo gitea/gitea \
    --namespace "$NAMESPACE" \
    --values "$REPO_DIR/charts/forgejo/values.yaml" \
    --wait \
    --timeout 5m

# Wait for pod to be ready
echo "⏳ Waiting for Forgejo to be ready..."
kubectl wait --for=condition=ready pod -l app.kubernetes.io/name=forgejo -n "$NAMESPACE" --timeout=300s

echo ""
echo "✅ Forgejo deployed successfully!"
echo ""
echo "🌐 Access Forgejo at: http://localhost:30080"
echo "🔑 SSH clone via: ssh://git@localhost:30022/<owner>/<repo>.git"
echo ""
echo "📋 Get admin password:"
echo "   kubectl get secret forgejo-admin-secret -n forgejo -o jsonpath='{.data.password}' | base64 -d"
