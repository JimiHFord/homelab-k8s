#!/bin/bash
# Port-forward Forgejo services to localhost

echo "🔗 Starting port-forwards..."

# Kill existing
pkill -f "kubectl port-forward.*forgejo" 2>/dev/null

# HTTP (web UI)
kubectl port-forward -n forgejo svc/forgejo-gitea-http 3000:3000 --address 0.0.0.0 &

# SSH (git operations)  
kubectl port-forward -n forgejo svc/forgejo-gitea-ssh 2222:22 --address 0.0.0.0 &

echo ""
echo "✅ Forgejo available at:"
echo "   Web:  http://localhost:3000"
echo "   SSH:  ssh://git@localhost:2222/<owner>/<repo>.git"
echo ""
echo "Press Ctrl+C to stop"
wait
