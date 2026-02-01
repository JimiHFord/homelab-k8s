# Homelab K8s

Helm charts and Kubernetes manifests for Mac mini homelab running Colima + k3s.

## Prerequisites

- macOS with [Colima](https://github.com/abiosoft/colima) installed
- Kubernetes enabled: `colima start --kubernetes`
- Helm 3: `brew install helm`
- kubectl: `brew install kubectl`

## Quick Start

```bash
# Start Colima with Kubernetes
colima start --kubernetes --cpu 4 --memory 8 --disk 60

# Add Helm repos
helm repo add forgejo https://codeberg.org/forgejo-contrib/forgejo-helm
helm repo update

# Deploy Forgejo
./scripts/deploy-forgejo.sh

# Set up native runner on Mac mini
./scripts/setup-runner.sh
```

## Components

| Service | URL | Description |
|---------|-----|-------------|
| Forgejo | https://forgejo.fords.cloud | Git forge |
| Grafana | https://grafana.fords.cloud | Dashboards |
| Vault | https://vault.fords.cloud | Secrets management |
| Keycloak | https://sso.fords.cloud | SSO/Identity |
| OpenClaw | https://claw.fords.cloud | AI assistant gateway |

### Forgejo

Self-hosted Git forge (Gitea fork). Deployed via Helm with:
- Persistent storage via local-path provisioner
- Exposed via Cloudflare tunnel
- SQLite database (suitable for single-node homelab)

### Vault

HashiCorp Vault for secrets management. Features:
- Auto-unseal via GCP KMS (no manual intervention on restart)
- KV v2 secrets engine enabled at `secret/`
- Web UI available

See [docs/vault.md](docs/vault.md) for usage guide.

### Forgejo Runner

Native runner on Mac mini for CI/CD. Runs outside the cluster for:
- Full access to host tools (Xcode, Homebrew, etc.)
- Better performance (no container overhead)
- macOS-specific builds

## Directory Structure

```
├── charts/
│   └── forgejo/          # Forgejo Helm values
├── docs/
│   └── vault.md          # Vault usage guide
├── manifests/            # Raw K8s manifests
├── scripts/
│   ├── deploy-forgejo.sh # Deploy/upgrade Forgejo
│   └── setup-runner.sh   # Set up native runner
└── README.md
```

## Backup

All persistent data is stored in Colima's VM disk. To backup:

```bash
# Stop Colima
colima stop

# Backup the VM disk
cp -r ~/.colima ~/.colima-backup-$(date +%Y%m%d)

# Restart
colima start --kubernetes
```

## Restore on New Machine

```bash
# Install prerequisites
brew install colima kubectl helm

# Start Colima
colima start --kubernetes --cpu 4 --memory 8 --disk 60

# Clone this repo
git clone https://github.com/JimiHFord/homelab-k8s.git
cd homelab-k8s

# Deploy everything
./scripts/deploy-forgejo.sh
./scripts/setup-runner.sh
```
