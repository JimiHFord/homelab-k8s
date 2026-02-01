#!/bin/bash
set -euo pipefail

# Configure Keycloak: LDAP federation + Vault OIDC client
#
# Required environment variables:
#   KC_ADMIN_USER     - Keycloak admin username
#   KC_ADMIN_PASS     - Keycloak admin password  
#   LLDAP_ADMIN_PASS  - LLDAP bind password
#
# Optional:
#   KC_URL            - Keycloak URL (default: https://sso.fords.cloud)
#   KC_REALM          - Realm name (default: master)

KC_URL="${KC_URL:-https://sso.fords.cloud}"
KC_REALM="${KC_REALM:-master}"

echo "🔐 Configuring Keycloak at $KC_URL"

# Get admin token
echo "→ Getting admin token..."
KC_TOKEN=$(curl -sf -X POST "$KC_URL/realms/master/protocol/openid-connect/token" \
  -H "Content-Type: application/x-www-form-urlencoded" \
  -d "username=$KC_ADMIN_USER" \
  -d "password=$KC_ADMIN_PASS" \
  -d "grant_type=password" \
  -d "client_id=admin-cli" | jq -r '.access_token')

if [ -z "$KC_TOKEN" ] || [ "$KC_TOKEN" = "null" ]; then
  echo "❌ Failed to get admin token"
  exit 1
fi
echo "✓ Got admin token"

# Helper to refresh token (they expire)
refresh_token() {
  KC_TOKEN=$(curl -sf -X POST "$KC_URL/realms/master/protocol/openid-connect/token" \
    -H "Content-Type: application/x-www-form-urlencoded" \
    -d "username=$KC_ADMIN_USER" \
    -d "password=$KC_ADMIN_PASS" \
    -d "grant_type=password" \
    -d "client_id=admin-cli" | jq -r '.access_token')
}

#
# 1. LDAP Federation
#
echo "→ Creating LDAP federation..."
LDAP_EXISTS=$(curl -sf "$KC_URL/admin/realms/$KC_REALM/components?type=org.keycloak.storage.UserStorageProvider" \
  -H "Authorization: Bearer $KC_TOKEN" | jq -r '.[] | select(.name=="lldap") | .id')

if [ -n "$LDAP_EXISTS" ]; then
  echo "✓ LDAP federation already exists (id: $LDAP_EXISTS)"
  LDAP_ID="$LDAP_EXISTS"
else
  LDAP_ID=$(curl -sf -X POST "$KC_URL/admin/realms/$KC_REALM/components" \
    -H "Authorization: Bearer $KC_TOKEN" \
    -H "Content-Type: application/json" \
    -d '{
      "name": "lldap",
      "providerId": "ldap",
      "providerType": "org.keycloak.storage.UserStorageProvider",
      "config": {
        "enabled": ["true"],
        "priority": ["0"],
        "editMode": ["READ_ONLY"],
        "syncRegistrations": ["false"],
        "vendor": ["other"],
        "connectionUrl": ["ldap://lldap.lldap.svc.cluster.local:389"],
        "bindDn": ["uid=admin,ou=people,dc=fords,dc=cloud"],
        "bindCredential": ["'"$LLDAP_ADMIN_PASS"'"],
        "usersDn": ["ou=people,dc=fords,dc=cloud"],
        "usernameLDAPAttribute": ["uid"],
        "rdnLDAPAttribute": ["uid"],
        "uuidLDAPAttribute": ["uid"],
        "userObjectClasses": ["person"],
        "searchScope": ["1"],
        "pagination": ["true"],
        "importEnabled": ["true"],
        "batchSizeForSync": ["1000"],
        "fullSyncPeriod": ["-1"],
        "changedSyncPeriod": ["-1"],
        "trustEmail": ["true"],
        "connectionPooling": ["true"]
      }
    }' -w '%{http_code}' -o /tmp/ldap-response.json)
  
  if [ "$LDAP_ID" = "201" ]; then
    LDAP_ID=$(curl -sf "$KC_URL/admin/realms/$KC_REALM/components?type=org.keycloak.storage.UserStorageProvider" \
      -H "Authorization: Bearer $KC_TOKEN" | jq -r '.[] | select(.name=="lldap") | .id')
    echo "✓ Created LDAP federation (id: $LDAP_ID)"
  else
    echo "❌ Failed to create LDAP federation"
    cat /tmp/ldap-response.json
    exit 1
  fi
fi

# Add LDAP mappers
refresh_token
echo "→ Adding LDAP mappers..."

for MAPPER in "username:uid:username" "email:mail:email" "firstName:givenName:firstName" "lastName:sn:lastName"; do
  NAME=$(echo $MAPPER | cut -d: -f1)
  LDAP_ATTR=$(echo $MAPPER | cut -d: -f2)
  USER_ATTR=$(echo $MAPPER | cut -d: -f3)
  
  curl -sf -X POST "$KC_URL/admin/realms/$KC_REALM/components" \
    -H "Authorization: Bearer $KC_TOKEN" \
    -H "Content-Type: application/json" \
    -d '{
      "name": "'"$NAME"'",
      "providerId": "user-attribute-ldap-mapper",
      "providerType": "org.keycloak.storage.ldap.mappers.LDAPStorageMapper",
      "parentId": "'"$LDAP_ID"'",
      "config": {
        "ldap.attribute": ["'"$LDAP_ATTR"'"],
        "user.model.attribute": ["'"$USER_ATTR"'"],
        "read.only": ["true"],
        "always.read.value.from.ldap": ["false"],
        "is.mandatory.in.ldap": ["false"]
      }
    }' > /dev/null 2>&1 || true
done

# Group mapper
curl -sf -X POST "$KC_URL/admin/realms/$KC_REALM/components" \
  -H "Authorization: Bearer $KC_TOKEN" \
  -H "Content-Type: application/json" \
  -d '{
    "name": "groups",
    "providerId": "group-ldap-mapper",
    "providerType": "org.keycloak.storage.ldap.mappers.LDAPStorageMapper",
    "parentId": "'"$LDAP_ID"'",
    "config": {
      "groups.dn": ["ou=groups,dc=fords,dc=cloud"],
      "group.name.ldap.attribute": ["cn"],
      "group.object.classes": ["groupOfUniqueNames"],
      "preserve.group.inheritance": ["false"],
      "membership.ldap.attribute": ["uniqueMember"],
      "membership.attribute.type": ["DN"],
      "mode": ["READ_ONLY"],
      "user.roles.retrieve.strategy": ["LOAD_GROUPS_BY_MEMBER_ATTRIBUTE"],
      "drop.non.existing.groups.during.sync": ["false"]
    }
  }' > /dev/null 2>&1 || true

echo "✓ LDAP mappers configured"

#
# 2. Vault OIDC Client
#
refresh_token
echo "→ Creating Vault OIDC client..."

VAULT_CLIENT_EXISTS=$(curl -sf "$KC_URL/admin/realms/$KC_REALM/clients?clientId=vault" \
  -H "Authorization: Bearer $KC_TOKEN" | jq -r '.[0].id // empty')

if [ -n "$VAULT_CLIENT_EXISTS" ]; then
  echo "✓ Vault client already exists (id: $VAULT_CLIENT_EXISTS)"
  VAULT_CLIENT_ID="$VAULT_CLIENT_EXISTS"
else
  curl -sf -X POST "$KC_URL/admin/realms/$KC_REALM/clients" \
    -H "Authorization: Bearer $KC_TOKEN" \
    -H "Content-Type: application/json" \
    -d '{
      "clientId": "vault",
      "name": "HashiCorp Vault",
      "enabled": true,
      "protocol": "openid-connect",
      "publicClient": false,
      "standardFlowEnabled": true,
      "directAccessGrantsEnabled": false,
      "redirectUris": [
        "https://vault.fords.cloud/ui/vault/auth/oidc/oidc/callback",
        "http://localhost:8250/oidc/callback"
      ],
      "webOrigins": ["https://vault.fords.cloud"]
    }'
  
  VAULT_CLIENT_ID=$(curl -sf "$KC_URL/admin/realms/$KC_REALM/clients?clientId=vault" \
    -H "Authorization: Bearer $KC_TOKEN" | jq -r '.[0].id')
  echo "✓ Created Vault client (id: $VAULT_CLIENT_ID)"
fi

# Get client secret
VAULT_CLIENT_SECRET=$(curl -sf "$KC_URL/admin/realms/$KC_REALM/clients/$VAULT_CLIENT_ID/client-secret" \
  -H "Authorization: Bearer $KC_TOKEN" | jq -r '.value')

# Add groups mapper to vault client
refresh_token
echo "→ Adding groups mapper to Vault client..."
curl -sf -X POST "$KC_URL/admin/realms/$KC_REALM/clients/$VAULT_CLIENT_ID/protocol-mappers/models" \
  -H "Authorization: Bearer $KC_TOKEN" \
  -H "Content-Type: application/json" \
  -d '{
    "name": "groups",
    "protocol": "openid-connect",
    "protocolMapper": "oidc-group-membership-mapper",
    "config": {
      "full.path": "false",
      "id.token.claim": "true",
      "access.token.claim": "true",
      "claim.name": "groups",
      "userinfo.token.claim": "true"
    }
  }' > /dev/null 2>&1 || true
echo "✓ Groups mapper configured"

#
# 3. Create groups scope
#
refresh_token
echo "→ Creating groups client scope..."
GROUPS_SCOPE_EXISTS=$(curl -sf "$KC_URL/admin/realms/$KC_REALM/client-scopes" \
  -H "Authorization: Bearer $KC_TOKEN" | jq -r '.[] | select(.name=="groups") | .id // empty')

if [ -z "$GROUPS_SCOPE_EXISTS" ]; then
  curl -sf -X POST "$KC_URL/admin/realms/$KC_REALM/client-scopes" \
    -H "Authorization: Bearer $KC_TOKEN" \
    -H "Content-Type: application/json" \
    -d '{
      "name": "groups",
      "description": "Group membership",
      "protocol": "openid-connect",
      "attributes": {
        "include.in.token.scope": "true"
      }
    }'
  
  GROUPS_SCOPE_ID=$(curl -sf "$KC_URL/admin/realms/$KC_REALM/client-scopes" \
    -H "Authorization: Bearer $KC_TOKEN" | jq -r '.[] | select(.name=="groups") | .id')
  
  # Add mapper to scope
  curl -sf -X POST "$KC_URL/admin/realms/$KC_REALM/client-scopes/$GROUPS_SCOPE_ID/protocol-mappers/models" \
    -H "Authorization: Bearer $KC_TOKEN" \
    -H "Content-Type: application/json" \
    -d '{
      "name": "groups",
      "protocol": "openid-connect",
      "protocolMapper": "oidc-group-membership-mapper",
      "config": {
        "full.path": "false",
        "id.token.claim": "true",
        "access.token.claim": "true",
        "claim.name": "groups",
        "userinfo.token.claim": "true"
      }
    }'
  
  # Assign to vault client
  curl -sf -X PUT "$KC_URL/admin/realms/$KC_REALM/clients/$VAULT_CLIENT_ID/default-client-scopes/$GROUPS_SCOPE_ID" \
    -H "Authorization: Bearer $KC_TOKEN"
  
  echo "✓ Created and assigned groups scope"
else
  echo "✓ Groups scope already exists"
fi

#
# 4. Create vault-admins group
#
refresh_token
echo "→ Creating vault-admins group..."
VAULT_ADMINS_EXISTS=$(curl -sf "$KC_URL/admin/realms/$KC_REALM/groups?search=vault-admins" \
  -H "Authorization: Bearer $KC_TOKEN" | jq -r '.[] | select(.name=="vault-admins") | .id // empty')

if [ -z "$VAULT_ADMINS_EXISTS" ]; then
  curl -sf -X POST "$KC_URL/admin/realms/$KC_REALM/groups" \
    -H "Authorization: Bearer $KC_TOKEN" \
    -H "Content-Type: application/json" \
    -d '{"name": "vault-admins"}'
  echo "✓ Created vault-admins group"
else
  echo "✓ vault-admins group already exists"
fi

#
# 5. Sync LDAP users
#
refresh_token
echo "→ Syncing LDAP users..."
SYNC_RESULT=$(curl -sf -X POST "$KC_URL/admin/realms/$KC_REALM/user-storage/$LDAP_ID/sync?action=triggerFullSync" \
  -H "Authorization: Bearer $KC_TOKEN")
echo "✓ Sync complete: $(echo $SYNC_RESULT | jq -r '.status')"

#
# Done
#
echo ""
echo "════════════════════════════════════════════════════"
echo "✅ Keycloak configuration complete!"
echo ""
echo "Vault OIDC Client Secret: $VAULT_CLIENT_SECRET"
echo ""
echo "Save this secret to Bitwarden and use it for Vault OIDC config."
echo "════════════════════════════════════════════════════"
