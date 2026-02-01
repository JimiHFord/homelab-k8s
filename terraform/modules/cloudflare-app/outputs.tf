output "record_id" {
  description = "Cloudflare DNS record ID"
  value       = cloudflare_record.app.id
}

output "hostname" {
  description = "Full hostname"
  value       = cloudflare_record.app.hostname
}

output "fqdn" {
  description = "Fully qualified domain name"
  value       = "${var.subdomain}.${var.domain}"
}

output "url" {
  description = "HTTPS URL for the app"
  value       = "https://${var.subdomain}.${var.domain}"
}
