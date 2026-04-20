#!/bin/bash
# Refreshes the Anthropic OAuth access token in .env using the refresh token from keychain.
# Run every 50 minutes via LaunchAgent (tokens expire after ~1 hour).
set -euo pipefail

NANOCLAW_DIR="$(cd "$(dirname "$0")/.." && pwd)"
ENV_FILE="$NANOCLAW_DIR/.env"

# Extract refresh token from keychain
REFRESH_TOKEN=$(python3 -c "
import subprocess, json, sys
try:
    raw = subprocess.check_output(
        ['security', 'find-generic-password', '-s', 'Claude Code-credentials', '-w'],
        stderr=subprocess.DEVNULL
    ).decode().strip()
    d = json.loads(raw)
    token = d.get('claudeAiOauth', {}).get('refreshToken', '')
    if not token:
        sys.exit(1)
    print(token)
except Exception as e:
    sys.exit(1)
") || { echo "[refresh-token] ERROR: Could not read refresh token from keychain" >&2; exit 1; }

# Exchange refresh token for new access token
RESPONSE=$(curl -s -X POST https://platform.claude.com/v1/oauth/token \
  -H "Content-Type: application/json" \
  -d "{\"grant_type\":\"refresh_token\",\"refresh_token\":\"$REFRESH_TOKEN\",\"client_id\":\"9d1c250a-e61b-44d9-88ed-5944d1962f5e\",\"scope\":\"user:inference user:profile user:sessions:claude_code\"}")

ACCESS_TOKEN=$(echo "$RESPONSE" | python3 -c "
import sys, json
try:
    d = json.load(sys.stdin)
    t = d.get('access_token') or d.get('accessToken', '')
    if not t:
        print('ERROR: ' + str(d.get('error', {}).get('message', 'no access_token in response')), file=sys.stderr)
        sys.exit(1)
    print(t)
except Exception as e:
    print('ERROR: ' + str(e), file=sys.stderr)
    sys.exit(1)
") || { echo "[refresh-token] ERROR: Token refresh failed: $RESPONSE" >&2; exit 1; }

# Update .env — remove old entry and write fresh one
grep -v "^CLAUDE_CODE_OAUTH_TOKEN=" "$ENV_FILE" > "$ENV_FILE.tmp" 2>/dev/null || true
echo "CLAUDE_CODE_OAUTH_TOKEN=$ACCESS_TOKEN" >> "$ENV_FILE.tmp"
mv "$ENV_FILE.tmp" "$ENV_FILE"

echo "[refresh-token] OK: access token updated at $(date)"
