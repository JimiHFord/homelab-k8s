#!/bin/bash
set -e

RUNNER_DIR="$HOME/.forgejo-runner"
RUNNER_NAME="${RUNNER_NAME:-mac-mini}"
FORGEJO_URL="${FORGEJO_URL:-http://localhost:30080}"
LABELS="${LABELS:-macos,arm64,native}"

echo "🏃 Setting up Forgejo Runner..."

# Check prerequisites
command -v curl >/dev/null 2>&1 || { echo "❌ curl not found"; exit 1; }

# Create runner directory
mkdir -p "$RUNNER_DIR"
cd "$RUNNER_DIR"

# Download runner if not present
if [ ! -f "$RUNNER_DIR/forgejo-runner" ]; then
    echo "📥 Downloading Forgejo Runner..."
    
    # Get latest release for darwin-arm64
    RUNNER_VERSION=$(curl -s https://code.forgejo.org/api/v1/repos/forgejo/runner/releases/latest | grep -o '"tag_name":"[^"]*"' | cut -d'"' -f4)
    RUNNER_VERSION="${RUNNER_VERSION:-v5.0.3}"
    
    echo "   Version: $RUNNER_VERSION"
    
    curl -L -o forgejo-runner.xz \
        "https://code.forgejo.org/forgejo/runner/releases/download/${RUNNER_VERSION}/forgejo-runner-${RUNNER_VERSION#v}-darwin-arm64.xz"
    
    xz -d forgejo-runner.xz
    chmod +x forgejo-runner
    
    echo "✅ Runner downloaded"
fi

# Check if already registered
if [ -f "$RUNNER_DIR/.runner" ]; then
    echo "⚠️  Runner already registered. To re-register, delete $RUNNER_DIR/.runner"
else
    echo ""
    echo "📋 To register the runner, you need a registration token from Forgejo."
    echo ""
    echo "1. Go to: $FORGEJO_URL/admin/actions/runners"
    echo "   (Or for repo-specific: $FORGEJO_URL/<owner>/<repo>/settings/actions/runners)"
    echo ""
    echo "2. Click 'Create new runner' and copy the token"
    echo ""
    echo "3. Run this command with your token:"
    echo ""
    echo "   cd $RUNNER_DIR"
    echo "   ./forgejo-runner register --no-interactive \\"
    echo "       --instance '$FORGEJO_URL' \\"
    echo "       --token '<YOUR_TOKEN>' \\"
    echo "       --name '$RUNNER_NAME' \\"
    echo "       --labels '$LABELS'"
    echo ""
fi

# Create LaunchAgent for auto-start
PLIST_PATH="$HOME/Library/LaunchAgents/org.forgejo.runner.plist"

if [ ! -f "$PLIST_PATH" ]; then
    echo "📝 Creating LaunchAgent for auto-start..."
    
    cat > "$PLIST_PATH" << EOF
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
    <key>Label</key>
    <string>org.forgejo.runner</string>
    <key>ProgramArguments</key>
    <array>
        <string>$RUNNER_DIR/forgejo-runner</string>
        <string>daemon</string>
    </array>
    <key>WorkingDirectory</key>
    <string>$RUNNER_DIR</string>
    <key>RunAtLoad</key>
    <true/>
    <key>KeepAlive</key>
    <true/>
    <key>StandardOutPath</key>
    <string>$RUNNER_DIR/runner.log</string>
    <key>StandardErrorPath</key>
    <string>$RUNNER_DIR/runner.err</string>
    <key>EnvironmentVariables</key>
    <dict>
        <key>PATH</key>
        <string>/opt/homebrew/bin:/usr/local/bin:/usr/bin:/bin:/usr/sbin:/sbin</string>
    </dict>
</dict>
</plist>
EOF

    echo "✅ LaunchAgent created at $PLIST_PATH"
fi

echo ""
echo "📋 Quick reference:"
echo ""
echo "   Register runner:"
echo "   cd $RUNNER_DIR && ./forgejo-runner register"
echo ""
echo "   Start runner (manual):"
echo "   cd $RUNNER_DIR && ./forgejo-runner daemon"
echo ""
echo "   Start runner (launchd):"
echo "   launchctl load $PLIST_PATH"
echo ""
echo "   Stop runner:"
echo "   launchctl unload $PLIST_PATH"
echo ""
echo "   View logs:"
echo "   tail -f $RUNNER_DIR/runner.log"
