#!/bin/bash
# Keeps CLAUDE_CODE_OAUTH_TOKEN in .env fresh.
# - If keychain has a valid (non-expired) token: copy it to .env directly.
# - If keychain token is expired: exchange refresh token via OAuth endpoint.
# Run every 4 hours via LaunchAgent (tokens expire after ~1 hour).
set -euo pipefail

NANOCLAW_DIR="$(cd "$(dirname "$0")/.." && pwd)"
ENV_FILE="$NANOCLAW_DIR/.env"
CLIENT_ID="9d1c250a-e61b-44d9-88ed-5944d1962f5e"
TOKEN_URL="https://platform.claude.com/v1/oauth/token"

# Read OAuth data from keychain
read_keychain() {
  python3 -c "
import subprocess, json, sys
try:
    raw = subprocess.check_output(
        ['security', 'find-generic-password', '-s', 'Claude Code-credentials', '-w'],
        stderr=subprocess.DEVNULL
    ).decode().strip()
    d = json.loads(raw).get('claudeAiOauth', {})
    print(d.get('accessToken', ''))
    print(d.get('refreshToken', ''))
    print(d.get('expiresAt', 0))
except Exception as e:
    sys.exit(1)
"
}

# Write access token to .env
write_env() {
  local token="$1"
  grep -v "^CLAUDE_CODE_OAUTH_TOKEN=" "$ENV_FILE" > "$ENV_FILE.tmp" 2>/dev/null || true
  echo "CLAUDE_CODE_OAUTH_TOKEN=$token" >> "$ENV_FILE.tmp"
  mv "$ENV_FILE.tmp" "$ENV_FILE"
}

# Read keychain
KEYCHAIN_DATA=$(read_keychain) || {
  echo "[refresh-token] ERROR: Could not read keychain" >&2
  exit 1
}

ACCESS_TOKEN=$(echo "$KEYCHAIN_DATA" | sed -n '1p')
REFRESH_TOKEN=$(echo "$KEYCHAIN_DATA" | sed -n '2p')
EXPIRES_AT_MS=$(echo "$KEYCHAIN_DATA" | sed -n '3p')
NOW_MS=$(python3 -c "import time; print(int(time.time() * 1000))")

if [ -z "$ACCESS_TOKEN" ]; then
  echo "[refresh-token] ERROR: No access token in keychain. Run: claude auth login" >&2
  exit 1
fi

# If keychain token is still valid (with 5-min buffer), just copy it to .env
if [ "$EXPIRES_AT_MS" -gt $((NOW_MS + 300000)) ] 2>/dev/null; then
  write_env "$ACCESS_TOKEN"
  echo "[refresh-token] OK: copied valid keychain token to .env (expires in $(( (EXPIRES_AT_MS - NOW_MS) / 60000 )) min)"
  exit 0
fi

# Token is expired — try to refresh via OAuth endpoint
echo "[refresh-token] Token expired, refreshing via OAuth..."

if [ -z "$REFRESH_TOKEN" ]; then
  echo "[refresh-token] ERROR: No refresh token in keychain. Run: claude auth login" >&2
  exit 1
fi

RESPONSE=$(curl -s -X POST "$TOKEN_URL" \
  -H "Content-Type: application/json" \
  -d "{\"grant_type\":\"refresh_token\",\"refresh_token\":\"$REFRESH_TOKEN\",\"client_id\":\"$CLIENT_ID\",\"scope\":\"user:inference user:profile user:sessions:claude_code\"}")

NEW_TOKEN=$(echo "$RESPONSE" | python3 -c "
import sys, json
try:
    d = json.load(sys.stdin)
    t = d.get('access_token') or d.get('accessToken', '')
    if not t:
        msg = d.get('error', {})
        if isinstance(msg, dict):
            msg = msg.get('message', str(d))
        print('ERROR: ' + str(msg), file=sys.stderr)
        sys.exit(1)
    print(t)
except Exception as e:
    print('ERROR: ' + str(e), file=sys.stderr)
    sys.exit(1)
") || {
  echo "[refresh-token] ERROR: Refresh failed: $RESPONSE" >&2
  exit 1
}

write_env "$NEW_TOKEN"
echo "[refresh-token] OK: refreshed and updated .env at $(date)"
