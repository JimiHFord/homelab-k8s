# Outputs - secrets and useful values

output "service_urls" {
  description = "URLs for all services"
  value = {
    keycloak = "https://sso.${var.domain}"
    vault    = "https://vault.${var.domain}"
    lldap    = "https://ldap.${var.domain}"
    grafana  = "https://grafana.${var.domain}"
    forgejo  = "https://forgejo.${var.domain}"
    openclaw = "https://claw.${var.domain}"
  }
}

output "ldap_config" {
  description = "LDAP configuration for apps"
  value = {
    url      = "ldap://lldap.lldap.svc.cluster.local:389"
    base_dn  = var.lldap_base_dn
    bind_dn  = "uid=admin,ou=people,${var.lldap_base_dn}"
    users_dn = "ou=people,${var.lldap_base_dn}"
  }
}

output "oidc_config" {
  description = "OIDC configuration for apps"
  value = {
    issuer   = "${var.keycloak_url}/realms/master"
    auth_url = "${var.keycloak_url}/realms/master/protocol/openid-connect/auth"
    token_url = "${var.keycloak_url}/realms/master/protocol/openid-connect/token"
  }
}
