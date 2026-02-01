#!/bin/bash
set -euo pipefail

# Configure Vault OIDC authentication with Keycloak
#
# Required environment variables:
#   VAULT_TOKEN         - Vault root/admin token
#   VAULT_OIDC_SECRET   - Keycloak client secret for vault client
#
# Optional:
#   VAULT_ADDR          - Vault URL (default: https://vault.fords.cloud)
#   KC_URL              - Keycloak URL (default: https://sso.fords.cloud)
#   KC_REALM            - Keycloak realm (default: master)

export VAULT_ADDR="${VAULT_ADDR:-https://vault.fords.cloud}"
KC_URL="${KC_URL:-https://sso.fords.cloud}"
KC_REALM="${KC_REALM:-master}"

echo "🔐 Configuring Vault OIDC at $VAULT_ADDR"

# Check vault is accessible
if ! curl -sf "$VAULT_ADDR/v1/sys/health" > /dev/null; then
  echo "❌ Cannot reach Vault at $VAULT_ADDR"
  exit 1
fi

# Check if we can use vault CLI or need to use curl
if command -v vault &> /dev/null; then
  USE_CLI=true
  echo "→ Using vault CLI"
else
  USE_CLI=false
  echo "→ Using curl (vault CLI not found)"
fi

#
# 1. Enable OIDC auth method
#
echo "→ Enabling OIDC auth method..."
if [ "$USE_CLI" = true ]; then
  vault auth enable oidc 2>/dev/null || echo "  (already enabled)"
else
  curl -sf -X POST "$VAULT_ADDR/v1/sys/auth/oidc" \
    -H "X-Vault-Token: $VAULT_TOKEN" \
    -H "Content-Type: application/json" \
    -d '{"type": "oidc"}' 2>/dev/null || echo "  (already enabled)"
fi
echo "✓ OIDC auth enabled"

#
# 2. Configure OIDC provider
#
echo "→ Configuring OIDC provider..."
curl -sf -X POST "$VAULT_ADDR/v1/auth/oidc/config" \
  -H "X-Vault-Token: $VAULT_TOKEN" \
  -H "Content-Type: application/json" \
  -d '{
    "oidc_discovery_url": "'"$KC_URL/realms/$KC_REALM"'",
    "oidc_client_id": "vault",
    "oidc_client_secret": "'"$VAULT_OIDC_SECRET"'",
    "default_role": "default"
  }'
echo "✓ OIDC provider configured"

#
# 3. Create admin policy
#
echo "→ Creating admin policy..."
curl -sf -X PUT "$VAULT_ADDR/v1/sys/policies/acl/admin" \
  -H "X-Vault-Token: $VAULT_TOKEN" \
  -H "Content-Type: application/json" \
  -d '{
    "policy": "# Full admin access\npath \"*\" {\n  capabilities = [\"create\", \"read\", \"update\", \"delete\", \"list\", \"sudo\"]\n}"
  }'
echo "✓ Admin policy created"

#
# 4. Create admin role (requires vault-admins group)
#
echo "→ Creating admin OIDC role..."
curl -sf -X POST "$VAULT_ADDR/v1/auth/oidc/role/admin" \
  -H "X-Vault-Token: $VAULT_TOKEN" \
  -H "Content-Type: application/json" \
  -d '{
    "bound_audiences": ["vault"],
    "allowed_redirect_uris": [
      "https://vault.fords.cloud/ui/vault/auth/oidc/oidc/callback",
      "http://localhost:8250/oidc/callback"
    ],
    "user_claim": "preferred_username",
    "groups_claim": "groups",
    "bound_claims": {
      "groups": ["vault-admins"]
    },
    "token_policies": ["admin"],
    "token_ttl": "8h"
  }'
echo "✓ Admin role created"

#
# 5. Create default role (any authenticated user)
#
echo "→ Creating default OIDC role..."
curl -sf -X POST "$VAULT_ADDR/v1/auth/oidc/role/default" \
  -H "X-Vault-Token: $VAULT_TOKEN" \
  -H "Content-Type: application/json" \
  -d '{
    "bound_audiences": ["vault"],
    "allowed_redirect_uris": [
      "https://vault.fords.cloud/ui/vault/auth/oidc/oidc/callback",
      "http://localhost:8250/oidc/callback"
    ],
    "user_claim": "preferred_username",
    "token_policies": ["default"],
    "token_ttl": "1h"
  }'
echo "✓ Default role created"

#
# 6. Enable KV secrets engine (if not already)
#
echo "→ Enabling KV secrets engine..."
curl -sf -X POST "$VAULT_ADDR/v1/sys/mounts/secret" \
  -H "X-Vault-Token: $VAULT_TOKEN" \
  -H "Content-Type: application/json" \
  -d '{
    "type": "kv",
    "options": {"version": "2"}
  }' 2>/dev/null || echo "  (already enabled)"
echo "✓ KV secrets engine enabled"

#
# Done
#
echo ""
echo "════════════════════════════════════════════════════"
echo "✅ Vault OIDC configuration complete!"
echo ""
echo "Users can now login at: $VAULT_ADDR"
echo "  - Role 'admin': requires vault-admins group membership"
echo "  - Role 'default': any authenticated Keycloak user"
echo "════════════════════════════════════════════════════"
