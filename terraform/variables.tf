# Kubernetes
variable "kubeconfig_path" {
  description = "Path to kubeconfig file"
  type        = string
  default     = "~/.kube/config"
}

variable "kubeconfig_context" {
  description = "Kubernetes context to use"
  type        = string
  default     = "colima"
}

# Vault
variable "vault_addr" {
  description = "Vault server address"
  type        = string
  default     = "https://vault.fords.cloud"
}

# Keycloak
variable "keycloak_url" {
  description = "Keycloak server URL"
  type        = string
  default     = "https://sso.fords.cloud"
}

variable "keycloak_admin_user" {
  description = "Keycloak admin username"
  type        = string
  default     = "admin"
}

variable "keycloak_admin_password" {
  description = "Keycloak admin password"
  type        = string
  sensitive   = true
}

# Cloudflare
variable "cloudflare_zone_id" {
  description = "Cloudflare zone ID for fords.cloud"
  type        = string
}

variable "cloudflare_account_id" {
  description = "Cloudflare account ID"
  type        = string
}

variable "cloudflare_tunnel_id" {
  description = "Existing Cloudflare tunnel ID"
  type        = string
  default     = "6e8a2363-c60c-469a-a94b-1fc1ecdade1a"
}

# GCP
variable "gcp_project" {
  description = "GCP project ID"
  type        = string
  default     = "gcp-lab-475404"
}

variable "gcp_region" {
  description = "GCP region"
  type        = string
  default     = "us-east1"
}

# LLDAP
variable "lldap_admin_password" {
  description = "LLDAP admin password"
  type        = string
  sensitive   = true
}

variable "lldap_base_dn" {
  description = "LLDAP base DN"
  type        = string
  default     = "dc=fords,dc=cloud"
}

# Domain
variable "domain" {
  description = "Base domain for services"
  type        = string
  default     = "fords.cloud"
}
