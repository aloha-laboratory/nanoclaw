#!/bin/bash
# Installs (or updates) the token refresh LaunchAgent.
# Run once after setup, or whenever you want to change the interval.
set -euo pipefail

INTERVAL=${1:-10800}  # default: 3 hours (10800s). Pass different value as $1.
PLIST="$HOME/Library/LaunchAgents/com.nanoclaw.refresh-token.plist"
SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
LOG="$SCRIPT_DIR/../logs/refresh-token.log"

mkdir -p "$(dirname "$LOG")"

cat > "$PLIST" << EOF
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
  <key>Label</key><string>com.nanoclaw.refresh-token</string>
  <key>ProgramArguments</key>
  <array>
    <string>/bin/bash</string>
    <string>$SCRIPT_DIR/refresh-token.sh</string>
  </array>
  <key>StartInterval</key><integer>$INTERVAL</integer>
  <key>RunAtLoad</key><true/>
  <key>StandardOutPath</key><string>$LOG</string>
  <key>StandardErrorPath</key><string>$LOG</string>
</dict>
</plist>
EOF

launchctl unload "$PLIST" 2>/dev/null || true
launchctl load "$PLIST"
echo "OK: refresh-token LaunchAgent installed (interval: ${INTERVAL}s = $(( INTERVAL / 3600 ))h $(( (INTERVAL % 3600) / 60 ))m)"
