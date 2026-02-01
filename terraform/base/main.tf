# Base infrastructure - just Kubernetes resources
# No external providers (Keycloak, Vault, Cloudflare, GCP)
# 
# This can be tested on a clean k3s cluster

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

variable "kubeconfig_path" {
  type    = string
  default = "~/.kube/config"
}

variable "kubeconfig_context" {
  type    = string
  default = "default"
}

variable "domain" {
  type    = string
  default = "test.local"
}

variable "lldap_admin_password" {
  type      = string
  sensitive = true
}

variable "lldap_base_dn" {
  type    = string
  default = "dc=test,dc=local"
}

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

# Namespaces
locals {
  namespaces = ["vault", "keycloak", "lldap", "grafana"]
}

resource "kubernetes_namespace" "services" {
  for_each = toset(local.namespaces)
  metadata {
    name = each.key
  }
}

# LLDAP
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

resource "kubernetes_persistent_volume_claim" "lldap_data" {
  metadata {
    name      = "lldap-data"
    namespace = kubernetes_namespace.services["lldap"].metadata[0].name
  }
  spec {
    access_modes = ["ReadWriteOnce"]
    resources {
      requests = {
        storage = "1Gi"
      }
    }
  }
  wait_until_bound = false  # k3s local-path uses WaitForFirstConsumer
}

resource "kubernetes_deployment" "lldap" {
  metadata {
    name      = "lldap"
    namespace = kubernetes_namespace.services["lldap"].metadata[0].name
  }

  spec {
    replicas = 1
    selector {
      match_labels = {
        app = "lldap"
      }
    }
    template {
      metadata {
        labels = {
          app = "lldap"
        }
      }
      spec {
        container {
          name  = "lldap"
          image = "lldap/lldap:stable"

          env {
            name  = "LLDAP_LDAP_BASE_DN"
            value = var.lldap_base_dn
          }
          env {
            name  = "LLDAP_HTTP_URL"
            value = "https://ldap.${var.domain}"
          }
          env {
            name  = "TZ"
            value = "America/New_York"
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

          volume_mount {
            name       = "data"
            mount_path = "/data"
          }

          resources {
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

        volume {
          name = "data"
          persistent_volume_claim {
            claim_name = kubernetes_persistent_volume_claim.lldap_data.metadata[0].name
          }
        }
      }
    }
  }
}

resource "kubernetes_service" "lldap_ldap" {
  metadata {
    name      = "lldap"
    namespace = kubernetes_namespace.services["lldap"].metadata[0].name
  }
  spec {
    selector = {
      app = "lldap"
    }
    port {
      name        = "ldap"
      port        = 389
      target_port = 3890
    }
  }
}

resource "kubernetes_service" "lldap_web" {
  metadata {
    name      = "lldap-web"
    namespace = kubernetes_namespace.services["lldap"].metadata[0].name
  }
  spec {
    selector = {
      app = "lldap"
    }
    port {
      name        = "http"
      port        = 17170
      target_port = 17170
    }
  }
}

# Outputs
output "namespaces" {
  value = [for ns in kubernetes_namespace.services : ns.metadata[0].name]
}

output "lldap_ldap_service" {
  value = "${kubernetes_service.lldap_ldap.metadata[0].name}.${kubernetes_service.lldap_ldap.metadata[0].namespace}.svc.cluster.local:389"
}
