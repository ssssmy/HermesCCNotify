#!/usr/bin/env bash
# ============================================================
# HermesCCNotify bridge.sh
# Called by Claude Code hooks. Two modes:
#   Stop event        → fire-and-forget notification
#   Notification event → blocking: send question, wait for reply
# ============================================================
set -euo pipefail

NOTIFY_DIR="${HOME}/.hermesccnotify"
CONFIG_FILE="${NOTIFY_DIR}/config"
LOG_FILE="${NOTIFY_DIR}/bridge.log"
REPLIES_DIR="${NOTIFY_DIR}/replies"
HERMES_WEBHOOK="${HERMES_WEBHOOK:-http://localhost:8644/webhooks/hermesccnotify}"
HERMES_SECRET="${HERMES_SECRET:-your-hmac-secret-here}"
QUESTION_WEBHOOK="${QUESTION_WEBHOOK:-http://localhost:8644/webhooks/hermesccnotify-question}"
VERSION_MARKER="hermesccnotify-v1"

mkdir -p "${NOTIFY_DIR}" "${REPLIES_DIR}"
[ -f "${CONFIG_FILE}" ] && source "${CONFIG_FILE}" 2>/dev/null || true

log() { echo "[$(date -Iseconds)] $*" >> "${LOG_FILE}"; }

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

# Determine event type
EVENT_TYPE=$(echo "${INPUT}" | python3 -c "
import sys, json
try:
    d = json.load(sys.stdin)
    e = d.get('hook_event_name', d.get('hookEventName', ''))
    # Normalize
    e = e.strip()
    if e.lower() == 'stop': print('stop')
    elif e.lower() in ('notification', 'afteragentthought'): print('question')
    else: print('other')
except:
    print('other')
" 2>/dev/null || echo "other")

# ============================================================
# MODE: Question / Notification (blocking — wait for reply)
# ============================================================
if [ "${EVENT_TYPE}" = "question" ]; then
    log "Question event detected, entering blocking mode"

    # Extract question and session info
    QDATA=$(echo "${INPUT}" | python3 -c "
import sys, json
try: d = json.load(sys.stdin)
except: sys.exit(1)
session_id = d.get('session_id', 'unknown')
question = d.get('question', '')
cwd = d.get('cwd', '')
project = cwd.split('/')[-1] if cwd else 'unknown'
print(json.dumps({
    'session_id': session_id,
    'question': question,
    'project': project,
    'cwd': cwd,
}))
" 2>/dev/null || echo "")

    if [ -z "${QDATA}" ]; then
        log "ERROR: question parse failed"
        echo '{}'
        exit 0
    fi

    SESSION_ID=$(echo "${QDATA}" | python3 -c "import sys,json; print(json.load(sys.stdin)['session_id'])")
    QUESTION=$(echo "${QDATA}" | python3 -c "import sys,json; print(json.load(sys.stdin)['question'])")
    PROJECT=$(echo "${QDATA}" | python3 -c "import sys,json; print(json.load(sys.stdin)['project'])")

    log "Question: session=${SESSION_ID} q=${QUESTION:0:80}"

    # Send question to Hermes webhook
    QPAYLOAD=$(echo "${QDATA}" | python3 -c "
import sys, json
d = json.load(sys.stdin)
from datetime import datetime, timezone
d['timestamp'] = datetime.now(timezone.utc).strftime('%Y-%m-%dT%H:%M:%SZ')
d['type'] = 'question'
print(json.dumps(d))
")
    QSIG=$(hmac_sign "${QPAYLOAD}")
    QHTTP=$(curl -s -o /dev/null -w "%{http_code}" --noproxy '*' \
        -X POST "${QUESTION_WEBHOOK}" \
        -H "Content-Type: application/json" \
        -H "X-Hub-Signature-256: ${QSIG}" \
        -H "User-Agent: HermesCCNotify/1.0" \
        -d "${QPAYLOAD}" \
        --connect-timeout 3 --max-time 8 2>/dev/null || echo "000")
    log "Question webhook: HTTP ${QHTTP}"

    # Block and wait for reply file
    REPLY_FILE="${REPLIES_DIR}/${SESSION_ID}.reply"
    REPLY_TIMEOUT=86400  # 24 hours (matches hook timeout)

    log "Waiting for reply at ${REPLY_FILE} (timeout=${REPLY_TIMEOUT}s)"
    ELAPSED=0
    while [ ${ELAPSED} -lt ${REPLY_TIMEOUT} ]; do
        if [ -f "${REPLY_FILE}" ]; then
            ANSWER=$(cat "${REPLY_FILE}" 2>/dev/null)
            if [ -n "${ANSWER}" ]; then
                log "Reply received: ${ANSWER:0:80}"
                rm -f "${REPLY_FILE}"

                # Send answer back to Claude Code via stdout
                cat <<END_RESPONSE
{"hookSpecificOutput":{"hookEventName":"Notification","answer":"${ANSWER}"}}
END_RESPONSE
                log "Reply delivered to Claude Code"
                exit 0
            fi
        fi
        sleep 1
        ELAPSED=$((ELAPSED + 1))
    done

    log "Reply timeout after ${ELAPSED}s"
    echo '{}'
    exit 0
fi

# ============================================================
# MODE: Stop event (fire-and-forget notification)
# ============================================================

PAYLOAD=$(echo "${INPUT}" | python3 -c "
import sys, json, os

try: data = json.load(sys.stdin)
except: sys.exit(1)

session_id = data.get('session_id', 'unknown')
cwd = data.get('cwd', '')
transcript_path = data.get('transcript_path', '')
model = data.get('model', '')
stop_reason = data.get('stop_reason', data.get('stop_hook_active', ''))
stop_reason = 'end_turn' if stop_reason == False else (stop_reason or 'completed')
last_user = data.get('last_user_message', '')
last_assistant = data.get('last_assistant_message', '')

total_tokens = ''
if transcript_path and os.path.exists(transcript_path):
    try:
        with open(transcript_path) as f:
            lines = f.readlines()[-50:]
        for line in reversed(lines):
            try:
                entry = json.loads(line)
            except:
                continue
            t = entry.get('type', '')
            msg = entry.get('message', {})
            if t == 'assistant':
                if not model and msg.get('model'):
                    model = msg['model']
                if not stop_reason or stop_reason == 'completed':
                    sr = msg.get('stop_reason', '')
                    if sr: stop_reason = sr
                if not total_tokens:
                    u = msg.get('usage', {})
                    inp = u.get('input_tokens', 0)
                    out = u.get('output_tokens', 0)
                    if inp or out:
                        total_tokens = f'{inp}->{out}'
            if not last_user and t == 'user':
                content = msg.get('content', '')
                if isinstance(content, list):
                    content = ' '.join([c.get('text','') for c in content if isinstance(c, dict)])
                if content and content.strip():
                    last_user = content.strip()
            if model and last_user and total_tokens and stop_reason not in ('', 'completed'):
                break
    except:
        pass

project = cwd.split('/')[-1] if cwd else 'unknown'
from datetime import datetime, timezone
ts = datetime.now(timezone.utc).strftime('%Y-%m-%dT%H:%M:%SZ')

payload = {
    'session_id': session_id, 'project': project, 'cwd': cwd,
    'model': model or 'unknown',
    'stop_reason': stop_reason,
    'last_user_message': last_user[:200] if last_user else '(no prompt)',
    'last_assistant_message': last_assistant[:300] if last_assistant else '(no response)',
    'total_tokens': total_tokens or 'N/A', 'timestamp': ts,
    'transcript_path': transcript_path,
    'type': 'stop',
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

# --- macOS notification ---
if command -v osascript &>/dev/null; then
    TITLE="Claude Code · ${PROJECT}"
    BODY="${LAST_ASSISTANT:0:120}"
    [ -z "${BODY}" ] && BODY="Task completed (${STOP_REASON})"
    osascript -e "display notification \"${BODY}\" with title \"${TITLE}\" subtitle \"${MODEL}\" sound name \"Glass\"" 2>/dev/null || true
    log "macOS notification sent"
fi

# --- Hermes webhook ---
SIGNATURE=$(hmac_sign "${PAYLOAD}")
HTTP_CODE=$(curl -s -o /dev/null -w "%{http_code}" --noproxy '*' \
    -X POST "${HERMES_WEBHOOK}" \
    -H "Content-Type: application/json" \
    -H "X-Hub-Signature-256: ${SIGNATURE}" \
    -H "User-Agent: HermesCCNotify/1.0" \
    -d "${PAYLOAD}" \
    --connect-timeout 3 --max-time 8 2>/dev/null || echo "000")
log "Hermes webhook: HTTP ${HTTP_CODE}"

# --- Direct webhook ---
if [ -f "${CONFIG_FILE}" ]; then
    WEBHOOK_URL=$(grep -E '^WEBHOOK_URL=' "${CONFIG_FILE}" 2>/dev/null | cut -d= -f2- | tr -d '"' | tr -d "'" || echo "")
    if [ -n "${WEBHOOK_URL}" ]; then
        curl -s -X POST "${WEBHOOK_URL}" \
            -H "Content-Type: application/json" \
            -H "User-Agent: HermesCCNotify/1.0" \
            -d "${PAYLOAD}" \
            --connect-timeout 5 --max-time 10 >/dev/null 2>&1 || true
        log "Direct webhook delivered"
    fi
fi

log "Done: project=${PROJECT} reason=${STOP_REASON} hermes=${HTTP_CODE}"
exit 0
