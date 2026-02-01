# OpenTofu Modules

Reusable modules for common infrastructure patterns.

## cloudflare-tunnel

Deploys cloudflared to Kubernetes and manages tunnel ingress + DNS records.

### Usage

```hcl
module "tunnel" {
  source = "./modules/cloudflare-tunnel"

  tunnel_id               = "your-tunnel-id"
  tunnel_credentials_json = file("~/.cloudflared/tunnel.json")
  cloudflare_zone_id      = "your-zone-id"
  domain                  = "example.com"

  apps = [
    {
      hostname = "app1.example.com"
      service  = "http://app1.default.svc.cluster.local:8080"
    },
    {
      hostname = "app2.example.com"
      service  = "http://app2.default.svc.cluster.local:3000"
      create_dns = false  # Don't create DNS record
    },
  ]
}
```

### Inputs

| Name | Description | Type | Required |
|------|-------------|------|----------|
| tunnel_id | Cloudflare tunnel ID | string | yes |
| tunnel_credentials_json | Tunnel credentials JSON | string | yes |
| cloudflare_zone_id | Cloudflare zone ID | string | yes |
| domain | Base domain | string | yes |
| apps | List of apps to route | list(object) | no |
| namespace | K8s namespace | string | no |
| create_namespace | Create the namespace | bool | no |
| replicas | Number of replicas | number | no |

### Outputs

| Name | Description |
|------|-------------|
| namespace | Namespace where cloudflared is deployed |
| ingress_rules | Current ingress rules |
| dns_records | Created DNS records |

---

## cloudflare-app

Creates a DNS record pointing to an existing tunnel. Use when you just need DNS without managing the tunnel config.

### Usage

```hcl
module "wiki" {
  source = "./modules/cloudflare-app"

  zone_id    = "your-zone-id"
  tunnel_id  = "your-tunnel-id"
  subdomain  = "wiki"
  domain     = "example.com"
}

# Outputs: wiki.example.com
```

### Inputs

| Name | Description | Type | Required |
|------|-------------|------|----------|
| zone_id | Cloudflare zone ID | string | yes |
| tunnel_id | Cloudflare tunnel ID | string | yes |
| subdomain | Subdomain name | string | yes |
| domain | Base domain | string | yes |
| proxied | Proxy through Cloudflare | bool | no |

### Outputs

| Name | Description |
|------|-------------|
| record_id | DNS record ID |
| hostname | Full hostname |
| url | HTTPS URL |

---

## Adding a New App

To add a new app to the homelab:

### Option 1: Add to tunnel module (recommended)

Edit `cloudflare.tf` and add to the `apps` list:

```hcl
module "cloudflare_tunnel" {
  # ...
  apps = [
    # ... existing apps ...
    {
      hostname = "newapp.fords.cloud"
      service  = "http://newapp.newapp.svc.cluster.local:8080"
    },
  ]
}
```

Then:
```bash
tofu plan
tofu apply
```

### Option 2: Standalone DNS record

If you just need DNS and will manage the tunnel config separately:

```hcl
module "newapp_dns" {
  source = "./modules/cloudflare-app"

  zone_id    = var.cloudflare_zone_id
  tunnel_id  = var.cloudflare_tunnel_id
  subdomain  = "newapp"
  domain     = var.domain
}
```

Then manually add the ingress rule to the cloudflared config.
