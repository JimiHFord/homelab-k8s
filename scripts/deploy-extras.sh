#!/bin/bash
set -e

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_DIR="$(dirname "$SCRIPT_DIR")"

echo "🔧 Deploying Grafana and Vault..."

# Deploy Grafana
echo "📊 Deploying Grafana..."
kubectl create namespace grafana 2>/dev/null || true

# Create admin password if not exists
if ! kubectl get secret grafana-admin -n grafana >/dev/null 2>&1; then
    GRAFANA_PASSWORD=$(openssl rand -base64 16 | tr -d '=+/')
    kubectl create secret generic grafana-admin \
        --namespace grafana \
        --from-literal=password="$GRAFANA_PASSWORD"
    echo "📝 Grafana admin password: $GRAFANA_PASSWORD"
    echo "⚠️  Save this password!"
fi

kubectl apply -f "$REPO_DIR/manifests/grafana.yaml"

# Deploy Vault
echo "🔐 Deploying Vault..."
kubectl apply -f "$REPO_DIR/manifests/vault.yaml"

# Wait for pods
echo "⏳ Waiting for pods..."
kubectl wait --for=condition=ready pod -l app=grafana -n grafana --timeout=120s || true
kubectl wait --for=condition=ready pod -l app=vault -n vault --timeout=120s || true

echo ""
echo "✅ Deployments complete!"
echo ""
echo "📊 Grafana: https://grafana.fords.cloud"
echo "   Username: admin"
echo "   Password: kubectl get secret grafana-admin -n grafana -o jsonpath='{.data.password}' | base64 -d"
echo ""
echo "🔐 Vault: https://vault.fords.cloud"
echo "   Note: Vault needs to be initialized and unsealed on first run"
echo "   Run: kubectl exec -it -n vault deploy/vault -- vault operator init"
