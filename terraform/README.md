# Homelab OpenTofu Configuration

Infrastructure-as-Code for the Mac mini k8s homelab using OpenTofu (Terraform-compatible).

## Prerequisites

```bash
# Install OpenTofu
brew install opentofu

# Or use Terraform
brew install terraform
```

## Quick Start

```bash
cd terraform

# Copy example vars
cp terraform.tfvars.example terraform.tfvars
# Edit terraform.tfvars with your values

# Set sensitive environment variables
export VAULT_TOKEN="hvs.xxx"
export CLOUDFLARE_API_TOKEN="xxx"
export TF_VAR_keycloak_admin_password="xxx"
export TF_VAR_lldap_admin_password="xxx"

# Initialize
tofu init

# Plan (see what will change)
tofu plan

# Apply
tofu apply
```

## Structure

```
terraform/
├── versions.tf       # Provider versions
├── providers.tf      # Provider configuration
├── variables.tf      # Input variables
├── outputs.tf        # Output values
├── kubernetes.tf     # K8s namespaces, LLDAP, Grafana
├── helm.tf           # Helm releases (Forgejo, Keycloak)
├── keycloak.tf       # Keycloak config (LDAP, clients)
├── vault.tf          # Vault config (OIDC, policies)
└── modules/          # Reusable modules (future)
```

## Authentication

| Provider | Environment Variable |
|----------|---------------------|
| Kubernetes | `KUBECONFIG` |
| Vault | `VAULT_TOKEN` |
| Cloudflare | `CLOUDFLARE_API_TOKEN` |
| GCP | `GOOGLE_APPLICATION_CREDENTIALS` |
| Keycloak | `TF_VAR_keycloak_admin_password` |

## Deployment Order

OpenTofu handles dependencies automatically, but the logical order is:

1. **Kubernetes namespaces** - Created first
2. **Secrets** - Generated passwords stored in K8s secrets
3. **Deployments** - LLDAP, Grafana, Keycloak, Vault
4. **Keycloak config** - After Keycloak is running
5. **Vault config** - After Vault is running and Keycloak client exists

## State Management

By default, state is stored locally in `terraform.tfstate`. For team use:

```hcl
# Add to versions.tf for remote state
terraform {
  backend "s3" {
    bucket = "your-bucket"
    key    = "homelab/terraform.tfstate"
    region = "us-east-1"
  }
}
```

Or use Vault as backend:

```hcl
terraform {
  backend "consul" {
    address = "consul.example.com:8500"
    path    = "homelab/terraform"
  }
}
```

## Secrets

Secrets are handled via:
- **Input variables** - Passed via environment or tfvars
- **Random generation** - `random_password` resources for new secrets
- **Outputs** - Sensitive outputs for generated values

After apply, save generated secrets to Bitwarden:

```bash
tofu output -json | jq -r '.keycloak_admin_password.value'
tofu output -json | jq -r '.grafana_admin_password.value'
tofu output -json | jq -r '.vault_client_secret.value'
```

## Importing Existing Resources

If you have existing resources from manual deployment:

```bash
# Import existing namespace
tofu import 'kubernetes_namespace.services["vault"]' vault

# Import existing Keycloak client
tofu import keycloak_openid_client.vault master/vault
```

## Modules (Planned)

Future modules for reusability:

```hcl
# Example: Add a new app with tunnel + DNS
module "new_app" {
  source = "./modules/cloudflare-app"
  
  name      = "wiki"
  hostname  = "wiki.fords.cloud"
  service   = "http://wiki.wiki.svc.cluster.local:3000"
  tunnel_id = var.cloudflare_tunnel_id
}
```

## Troubleshooting

### Provider authentication errors

```bash
# Kubernetes
kubectl cluster-info  # Verify cluster access

# Vault
curl -s $VAULT_ADDR/v1/sys/health  # Verify Vault access

# Keycloak (wait for pod to be ready)
kubectl wait --for=condition=ready pod -l app=keycloak -n keycloak
```

### State drift

If manual changes were made:

```bash
# Refresh state from actual infrastructure
tofu refresh

# See what would change
tofu plan
```

### Destroy specific resources

```bash
# Destroy just the Vault config
tofu destroy -target=vault_auth_backend.oidc
```
