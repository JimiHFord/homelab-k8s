# Keycloak configuration
# Note: Keycloak itself is deployed via Helm, this configures it after deployment

data "keycloak_realm" "master" {
  realm = "master"
}

#
# LDAP User Federation
#
resource "keycloak_ldap_user_federation" "lldap" {
  name      = "lldap"
  realm_id  = data.keycloak_realm.master.id
  enabled   = true
  priority  = 0

  edit_mode = "READ_ONLY"
  vendor    = "OTHER"

  connection_url = "ldap://lldap.lldap.svc.cluster.local:389"
  bind_dn        = "uid=admin,ou=people,${var.lldap_base_dn}"
  bind_credential = var.lldap_admin_password

  users_dn                  = "ou=people,${var.lldap_base_dn}"
  username_ldap_attribute   = "uid"
  rdn_ldap_attribute        = "uid"
  uuid_ldap_attribute       = "uid"
  user_object_classes       = ["person"]
  
  search_scope              = "ONE_LEVEL"
  pagination                = true
  import_enabled            = true
  batch_size_for_sync       = 1000
  full_sync_period          = -1
  changed_sync_period       = -1
  trust_email               = true
  connection_pooling        = true
}

resource "keycloak_ldap_user_attribute_mapper" "username" {
  realm_id                = data.keycloak_realm.master.id
  ldap_user_federation_id = keycloak_ldap_user_federation.lldap.id
  name                    = "username"

  ldap_attribute        = "uid"
  user_model_attribute  = "username"
  read_only             = true
}

resource "keycloak_ldap_user_attribute_mapper" "email" {
  realm_id                = data.keycloak_realm.master.id
  ldap_user_federation_id = keycloak_ldap_user_federation.lldap.id
  name                    = "email"

  ldap_attribute        = "mail"
  user_model_attribute  = "email"
  read_only             = true
}

resource "keycloak_ldap_user_attribute_mapper" "first_name" {
  realm_id                = data.keycloak_realm.master.id
  ldap_user_federation_id = keycloak_ldap_user_federation.lldap.id
  name                    = "first name"

  ldap_attribute        = "givenName"
  user_model_attribute  = "firstName"
  read_only             = true
}

resource "keycloak_ldap_user_attribute_mapper" "last_name" {
  realm_id                = data.keycloak_realm.master.id
  ldap_user_federation_id = keycloak_ldap_user_federation.lldap.id
  name                    = "last name"

  ldap_attribute        = "sn"
  user_model_attribute  = "lastName"
  read_only             = true
}

resource "keycloak_ldap_group_mapper" "groups" {
  realm_id                = data.keycloak_realm.master.id
  ldap_user_federation_id = keycloak_ldap_user_federation.lldap.id
  name                    = "groups"

  ldap_groups_dn                 = "ou=groups,${var.lldap_base_dn}"
  group_name_ldap_attribute      = "cn"
  group_object_classes           = ["groupOfUniqueNames"]
  membership_ldap_attribute      = "uniqueMember"
  membership_attribute_type      = "DN"
  membership_user_ldap_attribute = "uid"
  mode                           = "READ_ONLY"
  user_roles_retrieve_strategy   = "LOAD_GROUPS_BY_MEMBER_ATTRIBUTE"
  drop_non_existing_groups_during_sync = false
}

#
# Vault OIDC Client
#
resource "keycloak_openid_client" "vault" {
  realm_id  = data.keycloak_realm.master.id
  client_id = "vault"
  name      = "HashiCorp Vault"

  enabled                      = true
  access_type                  = "CONFIDENTIAL"
  standard_flow_enabled        = true
  direct_access_grants_enabled = false

  valid_redirect_uris = [
    "https://vault.${var.domain}/ui/vault/auth/oidc/oidc/callback",
    "http://localhost:8250/oidc/callback"
  ]

  web_origins = ["https://vault.${var.domain}"]
}

resource "keycloak_openid_group_membership_protocol_mapper" "vault_groups" {
  realm_id  = data.keycloak_realm.master.id
  client_id = keycloak_openid_client.vault.id
  name      = "groups"

  claim_name = "groups"
  full_path  = false
}

#
# Groups
#
resource "keycloak_group" "vault_admins" {
  realm_id = data.keycloak_realm.master.id
  name     = "vault-admins"
}

#
# Outputs
#
output "vault_client_secret" {
  description = "Vault OIDC client secret (save to Bitwarden)"
  value       = keycloak_openid_client.vault.client_secret
  sensitive   = true
}
