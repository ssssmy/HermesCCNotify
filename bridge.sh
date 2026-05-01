#!/usr/bin/env bash
# ============================================================
# CodeNotify bridge.sh
# Called by Claude Code Stop hook. Reads event JSON from stdin,
# extracts key info, and delivers notifications.
# ============================================================
set -euo pipefail

NOTIFY_DIR="${HOME}/.code-notify"
EVENTS_DIR="${NOTIFY_DIR}/events"
CONFIG_FILE="${NOTIFY_DIR}/config"
LOG_FILE="${NOTIFY_DIR}/bridge.log"
VERSION_MARKER="code-notify-v1"

mkdir -p "${EVENTS_DIR}"

# --- logging ---
log() {
    echo "[$(date -Iseconds)] $*" >> "${LOG_FILE}"
}

# --- read and parse stdin ---
INPUT=$(cat)
if [ -z "${INPUT}" ]; then
    log "ERROR: empty stdin, skipping"
    exit 0
fi

# Extract fields with python3 for robust JSON parsing
PAYLOAD=$(echo "${INPUT}" | python3 -c "
import sys, json
try:
    data = json.load(sys.stdin)
except:
    sys.exit(1)

session_id = data.get('session_id', 'unknown')
cwd = data.get('cwd', '')
stop_reason = data.get('stop_reason', '')
model = data.get('model', '')
permission_mode = data.get('permission_mode', '')
transcript_path = data.get('transcript_path', '')

last_user = data.get('last_user_message', '')
last_assistant = data.get('last_assistant_message', '')

usage = data.get('usage', {})
total_tokens = ''
if isinstance(usage, dict):
    inp = usage.get('input_tokens', 0)
    out = usage.get('output_tokens', 0)
    if inp or out:
        total_tokens = f'{inp}->{out}'

project = cwd.split('/')[-1] if cwd else 'unknown'

from datetime import datetime, timezone
ts = datetime.now(timezone.utc).strftime('%Y-%m-%dT%H:%M:%SZ')

payload = {
    'session_id': session_id,
    'project': project,
    'cwd': cwd,
    'model': model,
    'stop_reason': stop_reason,
    'permission_mode': permission_mode,
    'last_user_message': last_user[:200] if last_user else '',
    'last_assistant_message': last_assistant[:300] if last_assistant else '',
    'total_tokens': total_tokens,
    'timestamp': ts,
    'transcript_path': transcript_path,
}

print(json.dumps(payload, ensure_ascii=False))
" 2>/dev/null || echo "")

if [ -z "${PAYLOAD}" ]; then
    log "ERROR: JSON parse failed"
    echo "${INPUT}" > "${EVENTS_DIR}/_parse_error.json"
    exit 0
fi

# Extract fields
SESSION_ID=$(echo "${PAYLOAD}" | python3 -c "import sys,json; d=json.load(sys.stdin); print(d.get('session_id',''))")
PROJECT=$(echo "${PAYLOAD}" | python3 -c "import sys,json; d=json.load(sys.stdin); print(d.get('project',''))")
MODEL=$(echo "${PAYLOAD}" | python3 -c "import sys,json; d=json.load(sys.stdin); print(d.get('model',''))")
STOP_REASON=$(echo "${PAYLOAD}" | python3 -c "import sys,json; d=json.load(sys.stdin); print(d.get('stop_reason',''))")
LAST_ASSISTANT=$(echo "${PAYLOAD}" | python3 -c "import sys,json; d=json.load(sys.stdin); print(d.get('last_assistant_message',''))")

# --- Write event file ---
TS=$(date +%s)
EVENT_FILE="${EVENTS_DIR}/${TS}-${SESSION_ID}.json"
echo "${PAYLOAD}" > "${EVENT_FILE}"
log "Event written: ${EVENT_FILE}"

# --- macOS notification ---
NOTIFY_TITLE="Claude Code - ${PROJECT}"
if [ -n "${LAST_ASSISTANT}" ]; then
    NOTIFY_BODY=$(echo "${LAST_ASSISTANT}" | head -c 120)
else
    NOTIFY_BODY="Task completed (${STOP_REASON})"
fi

if command -v osascript &>/dev/null; then
    osascript -e "display notification \"${NOTIFY_BODY}\" with title \"${NOTIFY_TITLE}\" subtitle \"${MODEL}\" sound name \"Glass\"" 2>/dev/null || true
    log "macOS notification sent"
fi

# --- Optional webhook delivery ---
if [ -f "${CONFIG_FILE}" ]; then
    WEBHOOK_URL=$(grep -E '^WEBHOOK_URL=' "${CONFIG_FILE}" 2>/dev/null | cut -d= -f2- | tr -d '"' | tr -d "'" || echo "")
    if [ -n "${WEBHOOK_URL}" ]; then
        curl -s -X POST "${WEBHOOK_URL}"             -H "Content-Type: application/json"             -H "User-Agent: CodeNotify/1.0"             -d "${PAYLOAD}"             --connect-timeout 5 --max-time 10 >/dev/null 2>&1 || true
        log "Webhook delivered"
    fi
fi

log "Done: session=${SESSION_ID} project=${PROJECT} reason=${STOP_REASON}"
exit 0
