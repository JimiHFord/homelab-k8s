#!/bin/bash
set -euo pipefail

# Full homelab setup automation
#
# This script deploys and configures all services.
# Secrets can be provided via environment variables or Bitwarden.
#
# Usage:
#   # With environment variables:
#   export KC_ADMIN_PASS=xxx LLDAP_ADMIN_PASS=xxx VAULT_TOKEN=xxx
#   ./setup-all.sh
#
#   # With Bitwarden (requires BW_SESSION):
#   ./setup-all.sh --bitwarden
#
# Prerequisites:
#   - kubectl configured for your cluster
#   - cloudflared authenticated
#   - (optional) bw CLI logged in and unlocked

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_DIR="$(dirname "$SCRIPT_DIR")"

USE_BITWARDEN=false
SKIP_DEPLOY=false

# Parse args
while [[ $# -gt 0 ]]; do
  case $1 in
    --bitwarden|-b)
      USE_BITWARDEN=true
      shift
      ;;
    --skip-deploy)
      SKIP_DEPLOY=true
      shift
      ;;
    *)
      echo "Unknown option: $1"
      exit 1
      ;;
  esac
done

echo "════════════════════════════════════════════════════"
echo "  Homelab Setup"
echo "════════════════════════════════════════════════════"
echo ""

#
# Load secrets from Bitwarden if requested
#
if [ "$USE_BITWARDEN" = true ]; then
  echo "📦 Loading secrets from Bitwarden..."
  
  if [ -z "${BW_SESSION:-}" ]; then
    echo "❌ BW_SESSION not set. Run: export BW_SESSION=\$(bw unlock --raw)"
    exit 1
  fi
  
  bw sync > /dev/null
  
  KC_ADMIN_PASS=$(bw get password "Keycloak Admin" 2>/dev/null || true)
  LLDAP_ADMIN_PASS=$(bw get password "LLDAP Admin" 2>/dev/null || true)
  VAULT_TOKEN=$(bw get item "HashiCorp Vault (Mac mini k8s)" 2>/dev/null | jq -r '.notes' | grep -oP '(?<=ROOT TOKEN ---\n).*' | head -1 || true)
  VAULT_OIDC_SECRET=$(bw get password "Vault OIDC Client (Keycloak)" 2>/dev/null || true)
  
  echo "✓ Loaded secrets from Bitwarden"
fi

#
# Validate required secrets
#
MISSING=""
[ -z "${KC_ADMIN_PASS:-}" ] && MISSING="$MISSING KC_ADMIN_PASS"
[ -z "${LLDAP_ADMIN_PASS:-}" ] && MISSING="$MISSING LLDAP_ADMIN_PASS"
[ -z "${VAULT_TOKEN:-}" ] && MISSING="$MISSING VAULT_TOKEN"

if [ -n "$MISSING" ]; then
  echo "❌ Missing required secrets:$MISSING"
  echo ""
  echo "Either set them as environment variables or use --bitwarden"
  exit 1
fi

export KC_ADMIN_USER="${KC_ADMIN_USER:-admin}"
export KC_ADMIN_PASS
export LLDAP_ADMIN_PASS
export VAULT_TOKEN

#
# Deploy manifests
#
if [ "$SKIP_DEPLOY" = false ]; then
  echo ""
  echo "📦 Deploying manifests..."
  
  for manifest in cloudflared keycloak vault lldap grafana; do
    if [ -f "$REPO_DIR/manifests/$manifest.yaml" ]; then
      echo "→ Applying $manifest..."
      kubectl apply -f "$REPO_DIR/manifests/$manifest.yaml"
    fi
  done
  
  echo ""
  echo "⏳ Waiting for pods to be ready..."
  kubectl wait --for=condition=ready pod -l app=keycloak -n keycloak --timeout=300s 2>/dev/null || true
  kubectl wait --for=condition=ready pod -l app=vault -n vault --timeout=300s 2>/dev/null || true
  kubectl wait --for=condition=ready pod -l app=lldap -n lldap --timeout=300s 2>/dev/null || true
  
  echo "✓ Manifests deployed"
fi

#
# Configure Keycloak
#
echo ""
echo "🔧 Configuring Keycloak..."
"$SCRIPT_DIR/configure-keycloak.sh"

#
# Configure Vault OIDC
#
if [ -n "${VAULT_OIDC_SECRET:-}" ]; then
  echo ""
  echo "🔧 Configuring Vault OIDC..."
  "$SCRIPT_DIR/configure-vault-oidc.sh"
else
  echo ""
  echo "⚠️  Skipping Vault OIDC (no VAULT_OIDC_SECRET)"
  echo "   Run configure-vault-oidc.sh manually after getting the client secret"
fi

#
# Deploy Forgejo
#
if [ "$SKIP_DEPLOY" = false ]; then
  echo ""
  echo "📦 Deploying Forgejo..."
  "$SCRIPT_DIR/deploy-forgejo.sh" || true
fi

#
# Done
#
echo ""
echo "════════════════════════════════════════════════════"
echo "✅ Setup complete!"
echo ""
echo "Services:"
echo "  • Keycloak:  https://sso.fords.cloud"
echo "  • Vault:     https://vault.fords.cloud"
echo "  • LLDAP:     https://ldap.fords.cloud"
echo "  • Grafana:   https://grafana.fords.cloud"
echo "  • Forgejo:   https://forgejo.fords.cloud"
echo "  • OpenClaw:  https://claw.fords.cloud"
echo "════════════════════════════════════════════════════"
