# Cloudflare Tunnel Module
# Deploys cloudflared to Kubernetes and manages ingress routes

terraform {
  required_providers {
    kubernetes = {
      source  = "hashicorp/kubernetes"
      version = ">= 2.0"
    }
    cloudflare = {
      source  = "cloudflare/cloudflare"
      version = ">= 4.0"
    }
  }
}

#
# Namespace
#
resource "kubernetes_namespace" "cloudflared" {
  count = var.create_namespace ? 1 : 0

  metadata {
    name = var.namespace
  }
}

locals {
  namespace = var.create_namespace ? kubernetes_namespace.cloudflared[0].metadata[0].name : var.namespace
  
  # Build ingress rules from apps
  ingress_rules = concat(
    [for app in var.apps : {
      hostname = app.hostname
      service  = app.service
    }],
    # Catch-all 404
    [{ service = "http_status:404" }]
  )
}

#
# Tunnel credentials secret
#
resource "kubernetes_secret" "tunnel_creds" {
  metadata {
    name      = "cloudflared-creds"
    namespace = local.namespace
  }

  data = {
    "credentials.json" = var.tunnel_credentials_json
  }
}

#
# Tunnel config
#
resource "kubernetes_config_map" "tunnel_config" {
  metadata {
    name      = "cloudflared-config"
    namespace = local.namespace
  }

  data = {
    "config.yaml" = yamlencode({
      tunnel           = var.tunnel_id
      credentials-file = "/etc/cloudflared/credentials.json"
      no-autoupdate    = true
      ingress          = local.ingress_rules
    })
  }
}

#
# Deployment
#
resource "kubernetes_deployment" "cloudflared" {
  metadata {
    name      = "cloudflared"
    namespace = local.namespace
  }

  spec {
    replicas = var.replicas

    selector {
      match_labels = {
        app = "cloudflared"
      }
    }

    template {
      metadata {
        labels = {
          app = "cloudflared"
        }
        annotations = {
          # Force restart when config changes
          "config-hash" = sha256(kubernetes_config_map.tunnel_config.data["config.yaml"])
        }
      }

      spec {
        container {
          name  = "cloudflared"
          image = "cloudflare/cloudflared:${var.cloudflared_version}"

          args = ["tunnel", "--config", "/etc/cloudflared/config.yaml", "run"]

          volume_mount {
            name       = "config"
            mount_path = "/etc/cloudflared/config.yaml"
            sub_path   = "config.yaml"
            read_only  = true
          }

          volume_mount {
            name       = "credentials"
            mount_path = "/etc/cloudflared/credentials.json"
            sub_path   = "credentials.json"
            read_only  = true
          }

          resources {
            requests = {
              cpu    = var.resources.requests.cpu
              memory = var.resources.requests.memory
            }
            limits = {
              cpu    = var.resources.limits.cpu
              memory = var.resources.limits.memory
            }
          }
        }

        volume {
          name = "config"
          config_map {
            name = kubernetes_config_map.tunnel_config.metadata[0].name
          }
        }

        volume {
          name = "credentials"
          secret {
            secret_name = kubernetes_secret.tunnel_creds.metadata[0].name
          }
        }
      }
    }
  }
}

#
# DNS Records
#
resource "cloudflare_record" "tunnel_dns" {
  for_each = { for app in var.apps : app.hostname => app if app.create_dns }

  zone_id = var.cloudflare_zone_id
  name    = replace(each.value.hostname, ".${var.domain}", "")
  type    = "CNAME"
  value   = "${var.tunnel_id}.cfargotunnel.com"
  proxied = true
  ttl     = 1  # Auto TTL when proxied
  
  comment = "Managed by OpenTofu - ${each.value.hostname}"
}
