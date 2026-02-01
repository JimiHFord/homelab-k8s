# Vault configuration
# Note: Vault deployment is in kubernetes.tf, this configures it after deployment

#
# OIDC Auth Method
#
resource "vault_auth_backend" "oidc" {
  type = "oidc"
}

resource "vault_jwt_auth_backend" "oidc" {
  path               = vault_auth_backend.oidc.path
  type               = "oidc"
  oidc_discovery_url = "${var.keycloak_url}/realms/master"
  oidc_client_id     = "vault"
  oidc_client_secret = keycloak_openid_client.vault.client_secret
  default_role       = "default"
}

#
# Policies
#
resource "vault_policy" "admin" {
  name = "admin"

  policy = <<-EOT
    # Full admin access
    path "*" {
      capabilities = ["create", "read", "update", "delete", "list", "sudo"]
    }
  EOT
}

resource "vault_policy" "readonly" {
  name = "readonly"

  policy = <<-EOT
    # Read-only access to secrets
    path "secret/data/*" {
      capabilities = ["read", "list"]
    }
    path "secret/metadata/*" {
      capabilities = ["read", "list"]
    }
  EOT
}

#
# OIDC Roles
#
resource "vault_jwt_auth_backend_role" "admin" {
  backend        = vault_jwt_auth_backend.oidc.path
  role_name      = "admin"
  role_type      = "oidc"

  bound_audiences   = ["vault"]
  user_claim        = "preferred_username"
  groups_claim      = "groups"
  token_policies    = [vault_policy.admin.name]
  token_ttl         = 28800  # 8 hours

  allowed_redirect_uris = [
    "https://vault.${var.domain}/ui/vault/auth/oidc/oidc/callback",
    "http://localhost:8250/oidc/callback"
  ]

  bound_claims = {
    groups = "vault-admins"
  }
}

resource "vault_jwt_auth_backend_role" "default" {
  backend        = vault_jwt_auth_backend.oidc.path
  role_name      = "default"
  role_type      = "oidc"

  bound_audiences   = ["vault"]
  user_claim        = "preferred_username"
  token_policies    = ["default"]
  token_ttl         = 3600  # 1 hour

  allowed_redirect_uris = [
    "https://vault.${var.domain}/ui/vault/auth/oidc/oidc/callback",
    "http://localhost:8250/oidc/callback"
  ]
}

#
# KV Secrets Engine
#
resource "vault_mount" "secret" {
  path        = "secret"
  type        = "kv"
  description = "KV Version 2 secret engine"

  options = {
    version = "2"
  }
}
