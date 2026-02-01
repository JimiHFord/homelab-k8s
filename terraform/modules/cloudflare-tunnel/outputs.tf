output "namespace" {
  description = "Namespace where cloudflared is deployed"
  value       = local.namespace
}

output "deployment_name" {
  description = "Name of the cloudflared deployment"
  value       = kubernetes_deployment.cloudflared.metadata[0].name
}

output "config_map_name" {
  description = "Name of the config map"
  value       = kubernetes_config_map.tunnel_config.metadata[0].name
}

output "ingress_rules" {
  description = "Current ingress rules"
  value       = local.ingress_rules
}

output "dns_records" {
  description = "Created DNS records"
  value = { for hostname, record in cloudflare_record.tunnel_dns : hostname => {
    id      = record.id
    name    = record.name
    value   = record.value
    proxied = record.proxied
  }}
}
