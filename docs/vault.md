# HashiCorp Vault

Secrets management for the homelab. Vault stores sensitive data (API keys, passwords, certs) and provides controlled access to them.

## Quick Reference

| Item | Value |
|------|-------|
| **URL** | https://vault.fords.cloud |
| **UI** | Yes (login with root token) |
| **Version** | 1.21.2 |
| **Storage** | File (PVC in k8s) |
| **Auto-unseal** | GCP KMS |

## Core Concepts

### Sealed vs Unsealed

Vault encrypts everything at rest. When it starts, it's **sealed** — it has encrypted data but can't read it.

- **Sealed**: Vault is locked. Can't read or write secrets. Health check returns `sealed: true`.
- **Unsealed**: Vault is operational. Can read/write secrets.

With auto-unseal (GCP KMS), Vault automatically unseals on startup. Without it, you'd need to manually provide unseal keys every time the pod restarts.

### Tokens

Everything in Vault requires a **token**. Think of it like a session cookie.

- **Root token**: God mode. Can do anything. Use sparingly.
- **Service tokens**: Limited permissions, created for specific apps/uses.

```bash
# Login with root token
vault login hvs.xxxxx

# Or set env var
export VAULT_TOKEN=hvs.xxxxx
export VAULT_ADDR=https://vault.fords.cloud
```

### Secrets Engines

Vault doesn't just store secrets — it can generate them too. Different "engines" handle different types:

| Engine | Purpose | Example |
|--------|---------|---------|
| **KV (v2)** | Static secrets | API keys, passwords |
| **Database** | Dynamic DB creds | Auto-rotating Postgres passwords |
| **PKI** | Certificates | Generate TLS certs on demand |
| **Transit** | Encryption as a service | Encrypt data without exposing keys |
| **SSH** | SSH access | Signed SSH certificates |

We have **KV v2** enabled at `secret/`.

## Common Operations

### Reading/Writing Secrets

```bash
# Write a secret
vault kv put secret/myapp/config api_key="abc123" db_pass="hunter2"

# Read it back
vault kv get secret/myapp/config

# Get just one field
vault kv get -field=api_key secret/myapp/config

# List secrets at a path
vault kv list secret/myapp

# Delete a secret
vault kv delete secret/myapp/config
```

### KV v2 Versioning

KV v2 keeps history. You can recover deleted secrets (within the retention period):

```bash
# See all versions
vault kv metadata get secret/myapp/config

# Get a specific version
vault kv get -version=2 secret/myapp/config

# Undelete version 3
vault kv undelete -versions=3 secret/myapp/config

# Permanently destroy a version
vault kv destroy -versions=1 secret/myapp/config
```

### Checking Status

```bash
# Health check (no auth needed)
curl -s https://vault.fords.cloud/v1/sys/health | jq .

# Seal status
vault status

# Who am I?
vault token lookup
```

## Integrating Apps

### Option 1: Direct API Access

App fetches secrets from Vault at runtime:

```bash
# Curl example
curl -s -H "X-Vault-Token: $VAULT_TOKEN" \
  https://vault.fords.cloud/v1/secret/data/myapp/config | jq .data.data
```

### Option 2: Vault Agent Sidecar

For Kubernetes apps, inject secrets as files or env vars using Vault Agent. Add annotations:

```yaml
annotations:
  vault.hashicorp.com/agent-inject: "true"
  vault.hashicorp.com/role: "myapp"
  vault.hashicorp.com/agent-inject-secret-config: "secret/data/myapp/config"
```

Requires Vault Agent Injector (not currently installed).

### Option 3: External Secrets Operator

Sync Vault secrets to Kubernetes Secrets. App reads regular k8s secrets, ESO keeps them updated.

```yaml
apiVersion: external-secrets.io/v1beta1
kind: ExternalSecret
metadata:
  name: myapp-secrets
spec:
  secretStoreRef:
    name: vault-backend
    kind: ClusterSecretStore
  target:
    name: myapp-secrets
  data:
    - secretKey: api_key
      remoteRef:
        key: secret/data/myapp/config
        property: api_key
```

Requires External Secrets Operator (not currently installed).

### Option 4: Init Container / Startup Script

Fetch secrets once at startup, inject into app:

```bash
#!/bin/bash
export API_KEY=$(vault kv get -field=api_key secret/myapp/config)
exec ./myapp
```

## Policies

Control who can access what with policies:

```hcl
# myapp-policy.hcl
path "secret/data/myapp/*" {
  capabilities = ["read", "list"]
}

path "secret/metadata/myapp/*" {
  capabilities = ["list"]
}
```

```bash
# Create the policy
vault policy write myapp myapp-policy.hcl

# Create a token with that policy
vault token create -policy=myapp -ttl=24h
```

## Auth Methods

How apps/users prove identity to get tokens:

| Method | Use Case |
|--------|----------|
| **Token** | Direct token |
| **OIDC** | SSO via Keycloak ✅ (configured) |
| **Kubernetes** | Pods authenticate via service account |
| **AppRole** | Apps authenticate with role ID + secret ID |
| **GitHub** | Users authenticate via GitHub |

### OIDC (Keycloak SSO)

Configured to use Keycloak at `sso.fords.cloud`:

| Role | Policy | Description |
|------|--------|-------------|
| `default` | default | Basic read access |
| `admin` | admin | Full access |

**To login via UI:**
1. Go to https://vault.fords.cloud
2. Method: **OIDC**
3. Role: `admin`
4. Click "Sign in with OIDC"
5. Authenticate with Keycloak

**To login via CLI:**
```bash
export VAULT_ADDR=https://vault.fords.cloud
vault login -method=oidc role=admin
```

Keycloak client credentials stored in Bitwarden: "Vault OIDC Client (Keycloak)"

## Recovery

If something goes wrong:

### Lost Root Token

Generate a new one using recovery keys (need 3 of 5):

```bash
vault operator generate-root -init
vault operator generate-root -nonce=<nonce> <recovery-key-1>
vault operator generate-root -nonce=<nonce> <recovery-key-2>
vault operator generate-root -nonce=<nonce> <recovery-key-3>
# Decode the output to get new root token
```

Recovery keys are stored in Bitwarden under "HashiCorp Vault (Mac mini k8s)".

### Vault Won't Start

1. Check pod logs: `kubectl logs -n vault <pod>`
2. Check GCP KMS permissions (service account needs `cloudkms.cryptoKeyEncrypterDecrypter` and `cloudkms.viewer`)
3. Check the PVC still has data: `kubectl get pvc -n vault`

### Data Loss

Vault data is on a PVC. If the PVC is gone, you'll need to reinitialize (and lose all secrets). Regular backups recommended for production.

## Our Setup

```
┌─────────────────────────────────────────────────────────┐
│                     Mac mini k8s                        │
│  ┌─────────────────────────────────────────────────┐   │
│  │  vault namespace                                 │   │
│  │  ┌─────────────┐     ┌──────────────────────┐   │   │
│  │  │ vault pod   │────▶│ PVC (vault-pvc)      │   │   │
│  │  │             │     │ /vault/data          │   │   │
│  │  └──────┬──────┘     └──────────────────────┘   │   │
│  │         │                                        │   │
│  └─────────┼────────────────────────────────────────┘   │
│            │                                             │
└────────────┼─────────────────────────────────────────────┘
             │ auto-unseal
             ▼
┌─────────────────────────────────────────────────────────┐
│                    GCP (gcp-lab-475404)                 │
│  ┌─────────────────────────────────────────────────┐   │
│  │  Cloud KMS                                       │   │
│  │  keyring: vault-unseal (us-east1)               │   │
│  │  key: vault-key                                  │   │
│  └─────────────────────────────────────────────────┘   │
└─────────────────────────────────────────────────────────┘
```

## Next Steps

Ideas for expanding the setup:

- [ ] **Kubernetes auth**: Let pods authenticate with their service account
- [ ] **External Secrets Operator**: Sync secrets to k8s secrets automatically
- [ ] **PKI engine**: Generate TLS certs for internal services
- [ ] **Keycloak OIDC**: Login to Vault UI via SSO
- [ ] **Audit logging**: Track who accessed what

## Resources

- [Vault Docs](https://developer.hashicorp.com/vault/docs)
- [KV v2 Secrets Engine](https://developer.hashicorp.com/vault/docs/secrets/kv/kv-v2)
- [GCP KMS Auto-unseal](https://developer.hashicorp.com/vault/docs/configuration/seal/gcpckms)
- [Kubernetes Auth](https://developer.hashicorp.com/vault/docs/auth/kubernetes)
