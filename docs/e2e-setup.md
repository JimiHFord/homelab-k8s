# E2E Test Infrastructure Setup

This guide explains how to set up the full E2E testing infrastructure that uses ephemeral Cloudflare tunnels.

## Architecture

```
┌─────────────────────────────────────────────────────────────────┐
│                     Forgejo Actions                             │
│                   (runs on Mac mini)                            │
├─────────────────────────────────────────────────────────────────┤
│  1. Create ephemeral tunnel: homelab-e2e-{run_id}              │
│  2. Create DNS: *.e2e-{run_id}.fords.cloud → tunnel            │
│  3. Start QEMU VM with k3s                                      │
│  4. Deploy: cloudflared, vault, keycloak, lldap, grafana       │
│  5. Run Playwright tests against public URLs                    │
│  6. ALWAYS cleanup: delete DNS, tunnel, k8s resources          │
└─────────────────────────────────────────────────────────────────┘
```

## Prerequisites

### 1. Forgejo Runner (Mac mini)

The Mac mini is registered as a self-hosted runner with labels:
- `self-hosted`, `macOS`, `ARM64`, `homelab`

Runner config: `~/.config/act_runner/config.yaml`
Service: `~/Library/LaunchAgents/com.forgejo.act_runner.plist`

```bash
# Check runner status
launchctl list | grep act_runner
tail -f ~/.config/act_runner/runner.log
```

### 2. QEMU VM

The test VM at `~/VMs/homelab-test/` provides an isolated k3s cluster.

```bash
# Start VM
~/VMs/homelab-test/instances/homelab-test/start-daemon.sh

# Or in tmux for persistence
tmux new-session -d -s homelab-vm "~/VMs/homelab-test/instances/homelab-test/start.sh"

# SSH access
ssh -p 2222 jimi@localhost
```

### 3. Required Tools

All must be available on the runner:
- `tofu` (OpenTofu)
- `kubectl`
- `cloudflared`
- `node` / `npm`

## Cloudflare API Token

Create a token at https://dash.cloudflare.com/profile/api-tokens with these permissions:

| Permission | Access |
|------------|--------|
| Account > Cloudflare Tunnel | Edit |
| Zone > DNS | Edit |
| Zone > Zone | Read |

Zone Resources: Include `fords.cloud`

## Forgejo Secrets

Add these secrets to your Forgejo repository or organization:

| Secret | Description | How to Get |
|--------|-------------|------------|
| `CLOUDFLARE_API_TOKEN` | API token with Tunnel + DNS permissions | Create at Cloudflare dashboard |
| `CLOUDFLARE_ACCOUNT_ID` | Your Cloudflare account ID | `77b5e76c372d55147dc4120e0fa18af5` |
| `CLOUDFLARE_ZONE_ID` | Zone ID for fords.cloud | Cloudflare dashboard → fords.cloud → Overview → Zone ID |
| `TEST_KEYCLOAK_PASSWORD` | Password for test Keycloak admin | Generate: `openssl rand -base64 16` |
| `TEST_LLDAP_PASSWORD` | Password for test LLDAP admin | Generate: `openssl rand -base64 16` |

### Getting Zone ID

```bash
# With API token
curl -s "https://api.cloudflare.com/client/v4/zones?name=fords.cloud" \
  -H "Authorization: Bearer YOUR_API_TOKEN" | jq '.result[0].id'
```

## Running Tests

### Manual Trigger

1. Go to Forgejo → homelab-k8s → Actions
2. Select "Full E2E Test" workflow
3. Click "Run workflow"
4. Optionally check "Keep infrastructure" for debugging

### Scheduled

Tests run automatically at 3 AM EST daily.

### Local Testing

```bash
cd tests/e2e

# Against production
TEST_PASSWORD=xxx npm test

# Against local VM
VAULT_URL=http://localhost:8200 \
KEYCLOAK_URL=http://localhost:8080 \
npm run test -- --project=smoke
```

## Cleanup Verification

The workflow always cleans up, but if something goes wrong:

```bash
# List orphaned tunnels
curl -s "https://api.cloudflare.com/client/v4/accounts/ACCOUNT_ID/cfd_tunnel" \
  -H "Authorization: Bearer API_TOKEN" | jq '.result[] | select(.name | startswith("homelab-e2e"))'

# Delete orphaned tunnel
curl -X DELETE "https://api.cloudflare.com/client/v4/accounts/ACCOUNT_ID/cfd_tunnel/TUNNEL_ID" \
  -H "Authorization: Bearer API_TOKEN"

# List orphaned DNS records
curl -s "https://api.cloudflare.com/client/v4/zones/ZONE_ID/dns_records" \
  -H "Authorization: Bearer API_TOKEN" | jq '.result[] | select(.name | contains("-e2e-"))'
```

## Troubleshooting

### Runner not picking up jobs

```bash
# Check runner log
tail -100 ~/.config/act_runner/runner.log

# Restart runner
launchctl unload ~/Library/LaunchAgents/com.forgejo.act_runner.plist
launchctl load ~/Library/LaunchAgents/com.forgejo.act_runner.plist
```

### VM not starting

```bash
# Check if ports are in use
lsof -i :2222
lsof -i :6443

# Kill stuck QEMU
pkill -9 qemu-system-aarch64

# Restart
~/VMs/homelab-test/instances/homelab-test/start-daemon.sh
```

### Tunnel not connecting

```bash
# Check cloudflared pod logs
kubectl logs -n cloudflared -l app=cloudflared

# Verify tunnel exists
curl -s "https://api.cloudflare.com/client/v4/accounts/ACCOUNT_ID/cfd_tunnel/TUNNEL_ID" \
  -H "Authorization: Bearer API_TOKEN"
```

### DNS not resolving

```bash
# Check DNS propagation
dig vault-e2e-12345.fords.cloud

# Verify record exists
curl -s "https://api.cloudflare.com/client/v4/zones/ZONE_ID/dns_records?name=vault-e2e-12345.fords.cloud" \
  -H "Authorization: Bearer API_TOKEN"
```
