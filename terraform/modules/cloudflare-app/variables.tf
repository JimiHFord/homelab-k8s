variable "zone_id" {
  description = "Cloudflare zone ID"
  type        = string
}

variable "tunnel_id" {
  description = "Cloudflare tunnel ID"
  type        = string
}

variable "subdomain" {
  description = "Subdomain (e.g., 'vault' for vault.fords.cloud)"
  type        = string
}

variable "domain" {
  description = "Base domain (e.g., fords.cloud)"
  type        = string
}

variable "proxied" {
  description = "Whether to proxy through Cloudflare"
  type        = bool
  default     = true
}

variable "ttl" {
  description = "TTL for DNS record (only used if not proxied)"
  type        = number
  default     = 3600
}

variable "comment" {
  description = "Comment for the DNS record"
  type        = string
  default     = ""
}
