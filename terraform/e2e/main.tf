# E2E Test Infrastructure
# Deploys a complete homelab stack with ephemeral Cloudflare tunnel
#
# This config is designed for:
# 1. CI/CD testing on ephemeral k3s clusters
# 2. Full stack deployment with public URLs
# 3. Automatic cleanup after tests

terraform {
  required_version = ">= 1.6"
  required_providers {
    kubernetes = {
      source  = "hashicorp/kubernetes"
      version = "~> 2.25"
    }
    helm = {
      source  = "hashicorp/helm"
      version = "~> 2.12"
    }
    random = {
      source  = "hashicorp/random"
      version = "~> 3.6"
    }
  }
}

# Variables
variable "kubeconfig_path" {
  type    = string
  default = "~/.kube/e2e-test.yaml"
}

variable "kubeconfig_context" {
  type    = string
  default = "default"
}

variable "run_id" {
  description = "Unique run ID for this E2E test"
  type        = string
}

variable "domain" {
  description = "Base domain"
  type        = string
  default     = "fords.cloud"
}

variable "tunnel_id" {
  description = "Cloudflare tunnel ID"
  type        = string
}

variable "tunnel_token" {
  description = "Cloudflare tunnel token"
  type        = string
  sensitive   = true
}

variable "keycloak_admin_password" {
  type      = string
  sensitive = true
}

variable "lldap_admin_password" {
  type      = string
  sensitive = true
}

# Providers
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

# Local values
locals {
  # Ephemeral hostnames for this run
  vault_hostname    = "vault-e2e-${var.run_id}.${var.domain}"
  keycloak_hostname = "sso-e2e-${var.run_id}.${var.domain}"
  lldap_hostname    = "ldap-e2e-${var.run_id}.${var.domain}"
  grafana_hostname  = "grafana-e2e-${var.run_id}.${var.domain}"
  forgejo_hostname  = "forgejo-e2e-${var.run_id}.${var.domain}"
  
  namespaces = ["cloudflared", "vault", "keycloak", "lldap", "grafana"]
}

# Namespaces
resource "kubernetes_namespace" "services" {
  for_each = toset(local.namespaces)
  metadata {
    name = each.key
    labels = {
      "e2e-run-id" = var.run_id
    }
  }
}

#
# CLOUDFLARED
#
resource "kubernetes_secret" "tunnel_token" {
  metadata {
    name      = "tunnel-credentials"
    namespace = kubernetes_namespace.services["cloudflared"].metadata[0].name
  }
  data = {
    token = var.tunnel_token
  }
}

resource "kubernetes_config_map" "tunnel_config" {
  metadata {
    name      = "cloudflared-config"
    namespace = kubernetes_namespace.services["cloudflared"].metadata[0].name
  }
  data = {
    "config.yaml" = yamlencode({
      tunnel = var.tunnel_id
      credentials-file = "/etc/cloudflared/creds/credentials.json"
      ingress = [
        {
          hostname = local.vault_hostname
          service  = "http://vault.vault.svc.cluster.local:8200"
        },
        {
          hostname = local.keycloak_hostname
          service  = "http://keycloak.keycloak.svc.cluster.local:8080"
        },
        {
          hostname = local.lldap_hostname
          service  = "http://lldap.lldap.svc.cluster.local:17170"
        },
        {
          hostname = local.grafana_hostname
          service  = "http://grafana.grafana.svc.cluster.local:3000"
        },
        {
          service = "http_status:404"
        }
      ]
    })
  }
}

resource "kubernetes_deployment" "cloudflared" {
  metadata {
    name      = "cloudflared"
    namespace = kubernetes_namespace.services["cloudflared"].metadata[0].name
  }
  spec {
    replicas = 1
    selector {
      match_labels = { app = "cloudflared" }
    }
    template {
      metadata {
        labels = { app = "cloudflared" }
      }
      spec {
        container {
          name  = "cloudflared"
          image = "cloudflare/cloudflared:latest"
          args  = ["tunnel", "--config", "/etc/cloudflared/config/config.yaml", "run"]
          
          env {
            name = "TUNNEL_TOKEN"
            value_from {
              secret_key_ref {
                name = kubernetes_secret.tunnel_token.metadata[0].name
                key  = "token"
              }
            }
          }
          
          volume_mount {
            name       = "config"
            mount_path = "/etc/cloudflared/config"
            read_only  = true
          }
        }
        volume {
          name = "config"
          config_map {
            name = kubernetes_config_map.tunnel_config.metadata[0].name
          }
        }
      }
    }
  }
}

#
# LLDAP
#
resource "random_password" "lldap_jwt_secret" {
  length  = 32
  special = false
}

resource "kubernetes_secret" "lldap_secrets" {
  metadata {
    name      = "lldap-secrets"
    namespace = kubernetes_namespace.services["lldap"].metadata[0].name
  }
  data = {
    LLDAP_JWT_SECRET     = random_password.lldap_jwt_secret.result
    LLDAP_LDAP_USER_PASS = var.lldap_admin_password
  }
}

resource "kubernetes_deployment" "lldap" {
  metadata {
    name      = "lldap"
    namespace = kubernetes_namespace.services["lldap"].metadata[0].name
  }
  spec {
    replicas = 1
    selector {
      match_labels = { app = "lldap" }
    }
    template {
      metadata {
        labels = { app = "lldap" }
      }
      spec {
        container {
          name  = "lldap"
          image = "lldap/lldap:stable"
          
          env {
            name  = "LLDAP_LDAP_BASE_DN"
            value = "dc=e2e,dc=test"
          }
          env {
            name  = "LLDAP_HTTP_URL"
            value = "https://${local.lldap_hostname}"
          }
          env_from {
            secret_ref {
              name = kubernetes_secret.lldap_secrets.metadata[0].name
            }
          }
          
          port {
            name           = "http"
            container_port = 17170
          }
          port {
            name           = "ldap"
            container_port = 3890
          }
        }
      }
    }
  }
}

resource "kubernetes_service" "lldap" {
  metadata {
    name      = "lldap"
    namespace = kubernetes_namespace.services["lldap"].metadata[0].name
  }
  spec {
    selector = { app = "lldap" }
    port {
      name        = "http"
      port        = 17170
      target_port = 17170
    }
    port {
      name        = "ldap"
      port        = 389
      target_port = 3890
    }
  }
}

#
# KEYCLOAK
#
resource "kubernetes_secret" "keycloak_admin" {
  metadata {
    name      = "keycloak-admin"
    namespace = kubernetes_namespace.services["keycloak"].metadata[0].name
  }
  data = {
    KEYCLOAK_ADMIN          = "admin"
    KEYCLOAK_ADMIN_PASSWORD = var.keycloak_admin_password
  }
}

resource "kubernetes_deployment" "keycloak" {
  metadata {
    name      = "keycloak"
    namespace = kubernetes_namespace.services["keycloak"].metadata[0].name
  }
  spec {
    replicas = 1
    selector {
      match_labels = { app = "keycloak" }
    }
    template {
      metadata {
        labels = { app = "keycloak" }
      }
      spec {
        container {
          name  = "keycloak"
          image = "quay.io/keycloak/keycloak:23.0"
          args  = ["start-dev"]
          
          env {
            name  = "KC_PROXY"
            value = "edge"
          }
          env {
            name  = "KC_HOSTNAME"
            value = local.keycloak_hostname
          }
          env {
            name  = "KC_HTTP_ENABLED"
            value = "true"
          }
          env_from {
            secret_ref {
              name = kubernetes_secret.keycloak_admin.metadata[0].name
            }
          }
          
          port {
            container_port = 8080
          }
          
          resources {
            requests = {
              memory = "512Mi"
              cpu    = "250m"
            }
            limits = {
              memory = "1Gi"
              cpu    = "1"
            }
          }
        }
      }
    }
  }
}

resource "kubernetes_service" "keycloak" {
  metadata {
    name      = "keycloak"
    namespace = kubernetes_namespace.services["keycloak"].metadata[0].name
  }
  spec {
    selector = { app = "keycloak" }
    port {
      port        = 8080
      target_port = 8080
    }
  }
}

#
# VAULT
#
resource "helm_release" "vault" {
  name       = "vault"
  repository = "https://helm.releases.hashicorp.com"
  chart      = "vault"
  version    = "0.27.0"
  namespace  = kubernetes_namespace.services["vault"].metadata[0].name
  
  set {
    name  = "server.dev.enabled"
    value = "true"  # Dev mode for testing - no need to unseal
  }
  
  set {
    name  = "server.dev.devRootToken"
    value = "e2e-root-token"
  }
  
  set {
    name  = "ui.enabled"
    value = "true"
  }
  
  set {
    name  = "ui.serviceType"
    value = "ClusterIP"
  }
}

#
# GRAFANA
#
resource "helm_release" "grafana" {
  name       = "grafana"
  repository = "https://grafana.github.io/helm-charts"
  chart      = "grafana"
  version    = "7.3.0"
  namespace  = kubernetes_namespace.services["grafana"].metadata[0].name
  
  set {
    name  = "adminUser"
    value = "admin"
  }
  
  set {
    name  = "adminPassword"
    value = var.keycloak_admin_password  # Reuse for simplicity
  }
  
  set {
    name  = "service.type"
    value = "ClusterIP"
  }
  
  set {
    name  = "persistence.enabled"
    value = "false"  # Ephemeral for testing
  }
}

# Outputs
output "urls" {
  value = {
    vault    = "https://${local.vault_hostname}"
    keycloak = "https://${local.keycloak_hostname}"
    lldap    = "https://${local.lldap_hostname}"
    grafana  = "https://${local.grafana_hostname}"
  }
}

output "test_credentials" {
  sensitive = true
  value = {
    keycloak_admin = {
      username = "admin"
      password = var.keycloak_admin_password
    }
    lldap_admin = {
      username = "admin"
      password = var.lldap_admin_password
    }
    vault_token = "e2e-root-token"
    grafana = {
      username = "admin"
      password = var.keycloak_admin_password
    }
  }
}
