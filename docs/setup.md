# Homelab Setup Guide

Complete setup guide for the Mac mini k8s homelab.

## Prerequisites

```bash
# Install tools
brew install colima kubectl helm cloudflared

# Start Colima with k3s
colima start --kubernetes --cpu 4 --memory 8 --disk 60 --vm-type vz --vz-rosetta
```

## Deployment Order

Deploy in this order (dependencies matter):

1. **Cloudflared** (ingress)
2. **Grafana** (optional, monitoring)
3. **Keycloak** (identity)
4. **Vault** (secrets)
5. **LLDAP** (directory)
6. **Forgejo** (git)

## 1. Cloudflared

```bash
# Create namespace
kubectl create namespace cloudflared

# Create secret from tunnel credentials
kubectl create secret generic cloudflared-creds \
  --namespace=cloudflared \
  --from-file=credentials.json=~/.cloudflared/6e8a2363-c60c-469a-a94b-1fc1ecdade1a.json

# Deploy
kubectl apply -f manifests/cloudflared.yaml

# Add DNS routes for each hostname
cloudflared tunnel route dns 6e8a2363-c60c-469a-a94b-1fc1ecdade1a claw.fords.cloud
cloudflared tunnel route dns 6e8a2363-c60c-469a-a94b-1fc1ecdade1a forgejo.fords.cloud
cloudflared tunnel route dns 6e8a2363-c60c-469a-a94b-1fc1ecdade1a grafana.fords.cloud
cloudflared tunnel route dns 6e8a2363-c60c-469a-a94b-1fc1ecdade1a vault.fords.cloud
cloudflared tunnel route dns 6e8a2363-c60c-469a-a94b-1fc1ecdade1a sso.fords.cloud
cloudflared tunnel route dns 6e8a2363-c60c-469a-a94b-1fc1ecdade1a ldap.fords.cloud
```

## 2. Keycloak

```bash
# Create namespace
kubectl create namespace keycloak

# Generate passwords
DB_PASS=$(openssl rand -base64 16 | tr -d '=+/')
ADMIN_PASS=$(openssl rand -base64 16 | tr -d '=+/')

# Create secrets
kubectl create secret generic keycloak-db-secret \
  --namespace=keycloak \
  --from-literal=POSTGRES_USER=keycloak \
  --from-literal=POSTGRES_PASSWORD="$DB_PASS" \
  --from-literal=POSTGRES_DB=keycloak

kubectl create secret generic keycloak-admin-secret \
  --namespace=keycloak \
  --from-literal=KEYCLOAK_ADMIN=admin \
  --from-literal=KEYCLOAK_ADMIN_PASSWORD="$ADMIN_PASS"

echo "Save to Bitwarden: admin / $ADMIN_PASS"

# Deploy
kubectl apply -f manifests/keycloak.yaml
```

## 3. Vault

```bash
# Create namespace
kubectl create namespace vault

# Create GCP credentials secret (for auto-unseal)
# First, create service account in GCP:
#   gcloud iam service-accounts create vault-unseal --display-name="Vault Auto-Unseal"
#   gcloud kms keyrings create vault-unseal --location=us-east1
#   gcloud kms keys create vault-key --location=us-east1 --keyring=vault-unseal --purpose=encryption
#   gcloud kms keys add-iam-policy-binding vault-key --location=us-east1 --keyring=vault-unseal \
#     --member="serviceAccount:vault-unseal@gcp-lab-475404.iam.gserviceaccount.com" \
#     --role="roles/cloudkms.cryptoKeyEncrypterDecrypter"
#   gcloud kms keys add-iam-policy-binding vault-key --location=us-east1 --keyring=vault-unseal \
#     --member="serviceAccount:vault-unseal@gcp-lab-475404.iam.gserviceaccount.com" \
#     --role="roles/cloudkms.viewer"
#   gcloud iam service-accounts keys create vault-unseal-sa.json \
#     --iam-account=vault-unseal@gcp-lab-475404.iam.gserviceaccount.com

kubectl create secret generic vault-gcp-creds \
  --namespace=vault \
  --from-file=credentials.json=vault-unseal-sa.json

# Deploy
kubectl apply -f manifests/vault.yaml

# Wait for pod
kubectl wait --for=condition=ready pod -l app=vault -n vault --timeout=120s

# Initialize Vault (first time only)
kubectl exec -n vault -it $(kubectl get pod -n vault -l app=vault -o name) -- vault operator init

# Save the unseal keys and root token to Bitwarden!
```

## 4. LLDAP

```bash
# Create namespace
kubectl create namespace lldap

# Generate secrets
JWT_SECRET=$(openssl rand -base64 32)
ADMIN_PASS=$(openssl rand -base64 16 | tr -d '=+/')

kubectl create secret generic lldap-secrets \
  --namespace=lldap \
  --from-literal=LLDAP_JWT_SECRET="$JWT_SECRET" \
  --from-literal=LLDAP_LDAP_USER_PASS="$ADMIN_PASS"

echo "Save to Bitwarden: admin / $ADMIN_PASS"

# Deploy
kubectl apply -f manifests/lldap.yaml
```

## 5. Forgejo

```bash
./scripts/deploy-forgejo.sh
```

---

## Manual Configuration

### Keycloak: Create User

1. Go to https://sso.fords.cloud
2. Login as admin
3. Go to Users → Add user
4. Set username, email, first/last name
5. Go to Credentials tab → Set password

### Keycloak: LDAP Federation (LLDAP)

1. Go to https://sso.fords.cloud/admin/master/console
2. User Federation → Add LDAP provider
3. Settings:
   - **Name:** lldap
   - **Vendor:** Other
   - **Connection URL:** `ldap://lldap.lldap.svc.cluster.local:389`
   - **Bind DN:** `uid=admin,ou=people,dc=fords,dc=cloud`
   - **Bind Credential:** (LLDAP admin password from Bitwarden)
   - **Edit Mode:** READ_ONLY
   - **Users DN:** `ou=people,dc=fords,dc=cloud`
   - **Username LDAP attribute:** uid
   - **RDN LDAP attribute:** uid
   - **UUID LDAP attribute:** uid
   - **User Object Classes:** person
4. Save, then go to Mappers tab
5. Add mapper for groups:
   - **Name:** groups
   - **Type:** group-ldap-mapper
   - **Groups DN:** `ou=groups,dc=fords,dc=cloud`
   - **Group Name LDAP Attribute:** cn
   - **Group Object Classes:** groupOfUniqueNames
   - **Membership LDAP Attribute:** uniqueMember
   - **Membership Attribute Type:** DN
   - **Mode:** READ_ONLY
6. Go back to Settings → Action → Sync all users

### Keycloak: Vault OIDC Client

1. Go to Clients → Create client
2. Settings:
   - **Client ID:** vault
   - **Client authentication:** ON
   - **Valid redirect URIs:**
     - `https://vault.fords.cloud/ui/vault/auth/oidc/oidc/callback`
     - `http://localhost:8250/oidc/callback`
   - **Web origins:** `https://vault.fords.cloud`
3. Save, go to Credentials tab, copy the Client Secret
4. Go to Client Scopes → vault-dedicated → Add mapper → By configuration → Group Membership
   - **Name:** groups
   - **Token Claim Name:** groups
   - **Full group path:** OFF
5. Save client secret to Bitwarden

### Vault: OIDC Auth Configuration

```bash
export VAULT_ADDR=https://vault.fords.cloud
export VAULT_TOKEN=<root-token>

# Enable OIDC auth
vault auth enable oidc

# Configure OIDC
vault write auth/oidc/config \
  oidc_discovery_url="https://sso.fords.cloud/realms/master" \
  oidc_client_id="vault" \
  oidc_client_secret="<client-secret-from-keycloak>" \
  default_role="default"

# Create admin policy
vault policy write admin - <<EOF
path "*" {
  capabilities = ["create", "read", "update", "delete", "list", "sudo"]
}
EOF

# Create admin role (requires vault-admins group)
vault write auth/oidc/role/admin \
  bound_audiences="vault" \
  allowed_redirect_uris="https://vault.fords.cloud/ui/vault/auth/oidc/oidc/callback" \
  allowed_redirect_uris="http://localhost:8250/oidc/callback" \
  user_claim="preferred_username" \
  groups_claim="groups" \
  bound_claims='{"groups": ["vault-admins"]}' \
  token_policies="admin" \
  token_ttl="8h"

# Create default role (any authenticated user)
vault write auth/oidc/role/default \
  bound_audiences="vault" \
  allowed_redirect_uris="https://vault.fords.cloud/ui/vault/auth/oidc/oidc/callback" \
  allowed_redirect_uris="http://localhost:8250/oidc/callback" \
  user_claim="preferred_username" \
  token_policies="default" \
  token_ttl="1h"
```

### Keycloak: Create vault-admins Group

1. Go to Groups → Create group
2. Name: `vault-admins`
3. Go to Users → select user → Groups → Join Group → vault-admins

Or via LLDAP:
1. Go to https://ldap.fords.cloud
2. Groups → Create group: vault-admins
3. Add users to the group
4. In Keycloak: User Federation → lldap → Sync all users

---

## Secrets Reference

All secrets stored in Bitwarden folder "OpenClaw":

| Item | Contains |
|------|----------|
| HashiCorp Vault (Mac mini k8s) | Root token, recovery keys, GCP KMS info |
| Vault OIDC Client (Keycloak) | Client ID + secret |
| Keycloak Admin | Admin username + password |
| LLDAP Admin | Admin username + password |
| Cloudflare Tunnel | Tunnel ID + credentials path |

---

## Troubleshooting

### Vault sealed after restart
Should auto-unseal via GCP KMS. If not:
```bash
kubectl logs -n vault -l app=vault
# Check for GCP permission errors
```

### Keycloak LDAP sync fails
```bash
kubectl logs -n keycloak -l app=keycloak | grep -i ldap
# Check connection URL and bind credentials
```

### Cloudflared not routing
```bash
kubectl logs -n cloudflared -l app=cloudflared
# Check tunnel registration and ingress rules
```
