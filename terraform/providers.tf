# Provider configurations
#
# Authentication is handled via environment variables:
#   KUBECONFIG              - Kubernetes config file
#   VAULT_ADDR              - Vault address
#   VAULT_TOKEN             - Vault root/admin token
#   KEYCLOAK_URL            - Keycloak URL
#   KEYCLOAK_CLIENT_ID      - Keycloak admin-cli client
#   KEYCLOAK_CLIENT_SECRET  - (optional) or use user/pass
#   KEYCLOAK_USER           - Keycloak admin username
#   KEYCLOAK_PASSWORD       - Keycloak admin password
#   CLOUDFLARE_API_TOKEN    - Cloudflare API token
#   GOOGLE_CREDENTIALS      - GCP service account JSON (or use GOOGLE_APPLICATION_CREDENTIALS)

provider "kubernetes" {
  config_path    = var.kubeconfig_path
  config_context = var.kubeconfig_context
}

provider "helm" {
  kubernetes {
    config_path    = var.kubeconfig_path
    config_context = var.kubeconfig_context
  }
}

provider "vault" {
  address = var.vault_addr
  # Token from VAULT_TOKEN env var
}

provider "keycloak" {
  url       = var.keycloak_url
  client_id = "admin-cli"
  username  = var.keycloak_admin_user
  password  = var.keycloak_admin_password
}

provider "cloudflare" {
  # API token from CLOUDFLARE_API_TOKEN env var
}

provider "google" {
  project = var.gcp_project
  region  = var.gcp_region
}
