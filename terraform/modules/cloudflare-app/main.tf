# Cloudflare App Module
# Creates DNS record for an app routed through existing tunnel
# 
# Note: This module only creates DNS records.
# Ingress rules must be added to the tunnel config separately.
# Use the cloudflare-tunnel module for full management.

terraform {
  required_providers {
    cloudflare = {
      source  = "cloudflare/cloudflare"
      version = ">= 4.0"
    }
  }
}

resource "cloudflare_record" "app" {
  zone_id = var.zone_id
  name    = var.subdomain
  type    = "CNAME"
  value   = "${var.tunnel_id}.cfargotunnel.com"
  proxied = var.proxied
  ttl     = var.proxied ? 1 : var.ttl
  
  comment = var.comment != "" ? var.comment : "Managed by OpenTofu - ${var.subdomain}.${var.domain}"
}
