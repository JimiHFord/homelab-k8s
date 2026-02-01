# Cloudflare Tunnel and DNS configuration

#
# Tunnel credentials from file
#
data "local_file" "tunnel_credentials" {
  filename = pathexpand(var.tunnel_credentials_path)
}

#
# Main tunnel with all apps
#
module "cloudflare_tunnel" {
  source = "./modules/cloudflare-tunnel"

  tunnel_id               = var.cloudflare_tunnel_id
  tunnel_credentials_json = data.local_file.tunnel_credentials.content
  cloudflare_zone_id      = var.cloudflare_zone_id
  domain                  = var.domain

  apps = [
    {
      hostname = "claw.${var.domain}"
      service  = "http://host.docker.internal:18789"
    },
    {
      hostname = "forgejo.${var.domain}"
      service  = "http://forgejo-gitea-http.forgejo.svc.cluster.local:3000"
    },
    {
      hostname = "grafana.${var.domain}"
      service  = "http://grafana.grafana.svc.cluster.local:3000"
    },
    {
      hostname = "vault.${var.domain}"
      service  = "http://vault.vault.svc.cluster.local:8200"
    },
    {
      hostname = "sso.${var.domain}"
      service  = "http://keycloak.keycloak.svc.cluster.local:8080"
    },
    {
      hostname = "ldap.${var.domain}"
      service  = "http://lldap.lldap.svc.cluster.local:17170"
    },
  ]

  # Use existing namespace from kubernetes.tf
  create_namespace = false
  namespace        = kubernetes_namespace.services["cloudflared"].metadata[0].name

  depends_on = [kubernetes_namespace.services]
}

#
# Outputs
#
output "tunnel_ingress_rules" {
  description = "Current tunnel ingress rules"
  value       = module.cloudflare_tunnel.ingress_rules
}

output "tunnel_dns_records" {
  description = "Created DNS records"
  value       = module.cloudflare_tunnel.dns_records
}
