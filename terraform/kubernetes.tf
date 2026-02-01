# Kubernetes namespaces and base resources

locals {
  namespaces = ["cloudflared", "vault", "keycloak", "lldap", "grafana", "forgejo"]
}

resource "kubernetes_namespace" "services" {
  for_each = toset(local.namespaces)

  metadata {
    name = each.key
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

          port {
            container_port = 17170
            name           = "http"
          }

          port {
            container_port = 3890
            name           = "ldap"
          }

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

resource "kubernetes_service" "lldap" {
  metadata {
    name      = "lldap"
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

    port {
      name        = "ldap"
      port        = 389
      target_port = 3890
    }
  }
}

#
# Grafana
#
resource "random_password" "grafana_admin" {
  length  = 16
  special = false
}

resource "kubernetes_secret" "grafana_admin" {
  metadata {
    name      = "grafana-admin"
    namespace = kubernetes_namespace.services["grafana"].metadata[0].name
  }

  data = {
    password = random_password.grafana_admin.result
  }
}

resource "kubernetes_persistent_volume_claim" "grafana" {
  metadata {
    name      = "grafana-pvc"
    namespace = kubernetes_namespace.services["grafana"].metadata[0].name
  }

  spec {
    access_modes       = ["ReadWriteOnce"]
    storage_class_name = "local-path"
    resources {
      requests = {
        storage = "5Gi"
      }
    }
  }
}

resource "kubernetes_deployment" "grafana" {
  metadata {
    name      = "grafana"
    namespace = kubernetes_namespace.services["grafana"].metadata[0].name
  }

  spec {
    replicas = 1

    selector {
      match_labels = {
        app = "grafana"
      }
    }

    template {
      metadata {
        labels = {
          app = "grafana"
        }
      }

      spec {
        security_context {
          fs_group    = 472
          run_as_user = 472
        }

        container {
          name  = "grafana"
          image = "grafana/grafana:latest"

          port {
            container_port = 3000
          }

          env {
            name = "GF_SECURITY_ADMIN_PASSWORD"
            value_from {
              secret_key_ref {
                name = kubernetes_secret.grafana_admin.metadata[0].name
                key  = "password"
              }
            }
          }

          env {
            name  = "GF_SERVER_ROOT_URL"
            value = "https://grafana.${var.domain}"
          }

          volume_mount {
            name       = "grafana-storage"
            mount_path = "/var/lib/grafana"
          }

          resources {
            requests = {
              cpu    = "100m"
              memory = "128Mi"
            }
            limits = {
              cpu    = "500m"
              memory = "512Mi"
            }
          }
        }

        volume {
          name = "grafana-storage"
          persistent_volume_claim {
            claim_name = kubernetes_persistent_volume_claim.grafana.metadata[0].name
          }
        }
      }
    }
  }
}

resource "kubernetes_service" "grafana" {
  metadata {
    name      = "grafana"
    namespace = kubernetes_namespace.services["grafana"].metadata[0].name
  }

  spec {
    selector = {
      app = "grafana"
    }

    port {
      port        = 3000
      target_port = 3000
    }
  }
}
