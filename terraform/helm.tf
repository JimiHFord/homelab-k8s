# Helm releases for complex applications

#
# Forgejo
#
resource "helm_release" "forgejo" {
  name       = "forgejo"
  repository = "oci://codeberg.org/forgejo-contrib"
  chart      = "forgejo"
  namespace  = kubernetes_namespace.services["forgejo"].metadata[0].name
  version    = "7.0.0"

  values = [
    yamlencode({
      image = {
        repository = "codeberg.org/forgejo/forgejo"
        tag        = "7"
      }
      
      gitea = {
        admin = {
          existingSecret = kubernetes_secret.forgejo_admin.metadata[0].name
        }
        
        config = {
          server = {
            DOMAIN      = "forgejo.${var.domain}"
            ROOT_URL    = "https://forgejo.${var.domain}"
            SSH_DOMAIN  = "forgejo.${var.domain}"
          }
          
          database = {
            DB_TYPE = "sqlite3"
          }
          
          service = {
            DISABLE_REGISTRATION = false
          }
        }
      }
      
      persistence = {
        enabled      = true
        size         = "10Gi"
        storageClass = "local-path"
      }
      
      redis-cluster = {
        enabled = true
      }
    })
  ]

  depends_on = [kubernetes_secret.forgejo_admin]
}

resource "random_password" "forgejo_admin" {
  length  = 16
  special = false
}

resource "kubernetes_secret" "forgejo_admin" {
  metadata {
    name      = "forgejo-admin"
    namespace = kubernetes_namespace.services["forgejo"].metadata[0].name
  }

  data = {
    username = "jimi"
    password = random_password.forgejo_admin.result
    email    = "jimi@${var.domain}"
  }
}

#
# Keycloak (using Bitnami chart for simpler setup)
#
resource "random_password" "keycloak_admin" {
  length  = 16
  special = false
}

resource "random_password" "keycloak_db" {
  length  = 16
  special = false
}

resource "kubernetes_secret" "keycloak_admin" {
  metadata {
    name      = "keycloak-admin-secret"
    namespace = kubernetes_namespace.services["keycloak"].metadata[0].name
  }

  data = {
    KEYCLOAK_ADMIN          = "admin"
    KEYCLOAK_ADMIN_PASSWORD = random_password.keycloak_admin.result
  }
}

resource "kubernetes_secret" "keycloak_db" {
  metadata {
    name      = "keycloak-db-secret"
    namespace = kubernetes_namespace.services["keycloak"].metadata[0].name
  }

  data = {
    POSTGRES_USER     = "keycloak"
    POSTGRES_PASSWORD = random_password.keycloak_db.result
    POSTGRES_DB       = "keycloak"
  }
}

# Using raw manifests for Keycloak since it's simpler than the Bitnami chart
resource "kubernetes_persistent_volume_claim" "keycloak_postgres" {
  metadata {
    name      = "keycloak-postgres-pvc"
    namespace = kubernetes_namespace.services["keycloak"].metadata[0].name
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

resource "kubernetes_deployment" "keycloak_postgres" {
  metadata {
    name      = "keycloak-postgres"
    namespace = kubernetes_namespace.services["keycloak"].metadata[0].name
  }

  spec {
    replicas = 1

    selector {
      match_labels = {
        app = "keycloak-postgres"
      }
    }

    template {
      metadata {
        labels = {
          app = "keycloak-postgres"
        }
      }

      spec {
        container {
          name  = "postgres"
          image = "postgres:16-alpine"

          port {
            container_port = 5432
          }

          env_from {
            secret_ref {
              name = kubernetes_secret.keycloak_db.metadata[0].name
            }
          }

          volume_mount {
            name       = "postgres-storage"
            mount_path = "/var/lib/postgresql/data"
          }

          resources {
            requests = {
              cpu    = "100m"
              memory = "256Mi"
            }
            limits = {
              cpu    = "500m"
              memory = "512Mi"
            }
          }
        }

        volume {
          name = "postgres-storage"
          persistent_volume_claim {
            claim_name = kubernetes_persistent_volume_claim.keycloak_postgres.metadata[0].name
          }
        }
      }
    }
  }
}

resource "kubernetes_service" "keycloak_postgres" {
  metadata {
    name      = "keycloak-postgres"
    namespace = kubernetes_namespace.services["keycloak"].metadata[0].name
  }

  spec {
    selector = {
      app = "keycloak-postgres"
    }

    port {
      port        = 5432
      target_port = 5432
    }
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
      match_labels = {
        app = "keycloak"
      }
    }

    template {
      metadata {
        labels = {
          app = "keycloak"
        }
      }

      spec {
        container {
          name  = "keycloak"
          image = "quay.io/keycloak/keycloak:latest"

          args = ["start", "--hostname=sso.${var.domain}", "--proxy-headers=xforwarded", "--http-enabled=true"]

          port {
            container_port = 8080
          }

          env {
            name  = "KC_DB"
            value = "postgres"
          }

          env {
            name  = "KC_DB_URL"
            value = "jdbc:postgresql://keycloak-postgres:5432/keycloak"
          }

          env {
            name = "KC_DB_USERNAME"
            value_from {
              secret_key_ref {
                name = kubernetes_secret.keycloak_db.metadata[0].name
                key  = "POSTGRES_USER"
              }
            }
          }

          env {
            name = "KC_DB_PASSWORD"
            value_from {
              secret_key_ref {
                name = kubernetes_secret.keycloak_db.metadata[0].name
                key  = "POSTGRES_PASSWORD"
              }
            }
          }

          env {
            name  = "KC_HOSTNAME"
            value = "sso.${var.domain}"
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

          resources {
            requests = {
              cpu    = "200m"
              memory = "512Mi"
            }
            limits = {
              cpu    = "1000m"
              memory = "1Gi"
            }
          }
        }
      }
    }
  }

  depends_on = [kubernetes_deployment.keycloak_postgres]
}

resource "kubernetes_service" "keycloak" {
  metadata {
    name      = "keycloak"
    namespace = kubernetes_namespace.services["keycloak"].metadata[0].name
  }

  spec {
    selector = {
      app = "keycloak"
    }

    port {
      port        = 8080
      target_port = 8080
    }
  }
}

#
# Outputs
#
output "keycloak_admin_password" {
  description = "Keycloak admin password (save to Bitwarden)"
  value       = random_password.keycloak_admin.result
  sensitive   = true
}

output "grafana_admin_password" {
  description = "Grafana admin password (save to Bitwarden)"
  value       = random_password.grafana_admin.result
  sensitive   = true
}

output "forgejo_admin_password" {
  description = "Forgejo admin password (save to Bitwarden)"
  value       = random_password.forgejo_admin.result
  sensitive   = true
}

output "lldap_admin_password" {
  description = "LLDAP admin password (from input variable)"
  value       = var.lldap_admin_password
  sensitive   = true
}
