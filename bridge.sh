#!/usr/bin/env bash
# ============================================================
# CodeNotify bridge.sh
# Called by Claude Code Stop hook.
# Reads event JSON from stdin, delivers notifications:
#   1. macOS system notification (always, instant)
#   2. POST to Hermes webhook -> messaging channels
#   3. Optional: direct webhook URL from config
# ============================================================
set -euo pipefail

NOTIFY_DIR="${HOME}/.code-notify"
CONFIG_FILE="${NOTIFY_DIR}/config"
LOG_FILE="${NOTIFY_DIR}/bridge.log"
HERMES_WEBHOOK="${HERMES_WEBHOOK:-http://localhost:8644/webhooks/claude-code-notify}"
HERMES_SECRET="${HERMES_SECRET:-your-hmac-secret-here}"
VERSION_MARKER="code-notify-v1"

mkdir -p "${NOTIFY_DIR}"

# Load local secrets (HERMES_WEBHOOK, HERMES_SECRET)
[ -f "${CONFIG_FILE}" ] && source "${CONFIG_FILE}" 2>/dev/null || true

log() { echo "[$(date -Iseconds)] $*" >> "${LOG_FILE}"; }

# --- hmac-sha256 helper ---
hmac_sign() {
    echo -n "$1" | python3 -c "
import sys, hmac, hashlib
key = '${HERMES_SECRET}'.encode()
msg = sys.stdin.buffer.read()
sig = hmac.new(key, msg, hashlib.sha256).hexdigest()
print(f'sha256={sig}')
"
}

# --- read and parse stdin ---
INPUT=$(cat)
if [ -z "${INPUT}" ]; then
    log "ERROR: empty stdin"
    exit 0
fi

PAYLOAD=$(echo "${INPUT}" | python3 -c "
import sys, json
try: data = json.load(sys.stdin)
except: sys.exit(1)

session_id = data.get('session_id', 'unknown')
cwd = data.get('cwd', '')
stop_reason = data.get('stop_reason', '')
model = data.get('model', '')
transcript_path = data.get('transcript_path', '')

last_user = data.get('last_user_message', '')
last_assistant = data.get('last_assistant_message', '')

usage = data.get('usage', {})
total_tokens = ''
if isinstance(usage, dict):
    inp = usage.get('input_tokens', 0)
    out = usage.get('output_tokens', 0)
    if inp or out: total_tokens = f'{inp}->{out}'

project = cwd.split('/')[-1] if cwd else 'unknown'

from datetime import datetime, timezone
ts = datetime.now(timezone.utc).strftime('%Y-%m-%dT%H:%M:%SZ')

payload = {
    'session_id': session_id, 'project': project, 'cwd': cwd,
    'model': model, 'stop_reason': stop_reason,
    'last_user_message': last_user[:200] if last_user else '',
    'last_assistant_message': last_assistant[:300] if last_assistant else '',
    'total_tokens': total_tokens, 'timestamp': ts,
    'transcript_path': transcript_path,
}
print(json.dumps(payload, ensure_ascii=False))
" 2>/dev/null || echo "")

if [ -z "${PAYLOAD}" ]; then
    log "ERROR: parse failed"
    exit 0
fi

PROJECT=$(echo "${PAYLOAD}" | python3 -c "import sys,json; print(json.load(sys.stdin).get('project',''))")
MODEL=$(echo "${PAYLOAD}" | python3 -c "import sys,json; print(json.load(sys.stdin).get('model',''))")
STOP_REASON=$(echo "${PAYLOAD}" | python3 -c "import sys,json; print(json.load(sys.stdin).get('stop_reason',''))")
LAST_ASSISTANT=$(echo "${PAYLOAD}" | python3 -c "import sys,json; print(json.load(sys.stdin).get('last_assistant_message',''))")

# --- 1. macOS notification (instant) ---
if command -v osascript &>/dev/null; then
    TITLE="Claude Code · ${PROJECT}"
    BODY="${LAST_ASSISTANT:0:120}"
    [ -z "${BODY}" ] && BODY="Task completed (${STOP_REASON})"
    osascript -e "display notification \"${BODY}\" with title \"${TITLE}\" subtitle \"${MODEL}\" sound name \"Glass\"" 2>/dev/null || true
    log "macOS notification sent"
fi

# --- 2. Hermes webhook (push to messaging channels) ---
SIGNATURE=$(hmac_sign "${PAYLOAD}")
HTTP_CODE=$(curl -s -o /dev/null -w "%{http_code}"     -X POST "${HERMES_WEBHOOK}"     -H "Content-Type: application/json"     -H "X-Hub-Signature-256: ${SIGNATURE}"     -H "User-Agent: CodeNotify/1.0"     -d "${PAYLOAD}"     --connect-timeout 3 --max-time 8 2>/dev/null || echo "000")
log "Hermes webhook: HTTP ${HTTP_CODE}"

# --- 3. Optional direct webhook (from config) ---
if [ -f "${CONFIG_FILE}" ]; then
    WEBHOOK_URL=$(grep -E '^WEBHOOK_URL=' "${CONFIG_FILE}" 2>/dev/null | cut -d= -f2- | tr -d '"' | tr -d "'" || echo "")
    if [ -n "${WEBHOOK_URL}" ]; then
        curl -s -X POST "${WEBHOOK_URL}"             -H "Content-Type: application/json"             -H "User-Agent: CodeNotify/1.0"             -d "${PAYLOAD}"             --connect-timeout 5 --max-time 10 >/dev/null 2>&1 || true
        log "Direct webhook delivered"
    fi
fi

log "Done: project=${PROJECT} reason=${STOP_REASON} hermes=${HTTP_CODE}"
exit 0
