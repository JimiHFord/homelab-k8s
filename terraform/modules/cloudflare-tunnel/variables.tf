variable "tunnel_id" {
  description = "Cloudflare tunnel ID"
  type        = string
}

variable "tunnel_credentials_json" {
  description = "Tunnel credentials JSON content"
  type        = string
  sensitive   = true
}

variable "cloudflare_zone_id" {
  description = "Cloudflare zone ID"
  type        = string
}

variable "domain" {
  description = "Base domain (e.g., fords.cloud)"
  type        = string
}

variable "apps" {
  description = "List of apps to route through the tunnel"
  type = list(object({
    hostname   = string  # e.g., "vault.fords.cloud"
    service    = string  # e.g., "http://vault.vault.svc.cluster.local:8200"
    create_dns = optional(bool, true)  # Create DNS record
  }))
  default = []
}

variable "namespace" {
  description = "Kubernetes namespace for cloudflared"
  type        = string
  default     = "cloudflared"
}

variable "create_namespace" {
  description = "Create the namespace"
  type        = bool
  default     = true
}

variable "replicas" {
  description = "Number of cloudflared replicas"
  type        = number
  default     = 1
}

variable "cloudflared_version" {
  description = "Cloudflared image version"
  type        = string
  default     = "latest"
}

variable "resources" {
  description = "Container resource requests/limits"
  type = object({
    requests = object({
      cpu    = string
      memory = string
    })
    limits = object({
      cpu    = string
      memory = string
    })
  })
  default = {
    requests = {
      cpu    = "50m"
      memory = "64Mi"
    }
    limits = {
      cpu    = "200m"
      memory = "128Mi"
    }
  }
}
