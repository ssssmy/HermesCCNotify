#!/usr/bin/env bash
# ============================================================
# HermesCCNotify install.sh
# Installs Stop hook into Claude Code settings.
# Usage: install.sh [--global] [--project DIR] [--webhook URL] [--force] [--dry-run]
# ============================================================
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
BRIDGE_PATH="${SCRIPT_DIR}/bridge.sh"
NOTIFY_DIR="${HOME}/.hermesccnotify"
CONFIG_FILE="${NOTIFY_DIR}/config"
VERSION_MARKER="hermesccnotify-v1"

RED='\033[0;31m'; GREEN='\033[0;32m'; YELLOW='\033[1;33m'; CYAN='\033[0;36m'; NC='\033[0m'

banner() {
    echo ""
    echo -e "${CYAN}  HermesCCNotify - Real-time Claude Code notifications${NC}"
    echo ""
}

usage() {
    echo "Usage: install.sh [OPTIONS]"
    echo ""
    echo "Options:"
    echo "  --global        Install into ~/.claude/settings.json (all projects)"
    echo "  --project DIR   Install into DIR/.claude/settings.json (single project)"
    echo "  --webhook URL   Set webhook URL for direct HTTP delivery"
    echo "  --force         Force reinstall"
    echo "  --dry-run       Preview without applying"
    echo "  -h, --help      Show this help"
    exit 0
}

SCOPE="global"; PROJECT_DIR=""; WEBHOOK_URL=""; FORCE=false; DRY_RUN=false

while [[ $# -gt 0 ]]; do
    case "$1" in
        --global) SCOPE="global"; shift ;;
        --project) PROJECT_DIR="$2"; SCOPE="project"; shift 2 ;;
        --webhook) WEBHOOK_URL="$2"; shift 2 ;;
        --force) FORCE=true; shift ;;
        --dry-run) DRY_RUN=true; shift ;;
        -h|--help) usage ;;
        *) echo -e "${RED}Unknown: $1${NC}"; usage ;;
    esac
done

if [ "${SCOPE}" = "global" ]; then
    SETTINGS_FILE="${HOME}/.claude/settings.json"
    SCOPE_LABEL="global (~/.claude/settings.json)"
else
    [ -z "${PROJECT_DIR}" ] && { echo -e "${RED}--project requires a directory${NC}"; exit 1; }
    SETTINGS_FILE="${PROJECT_DIR}/.claude/settings.json"
    SCOPE_LABEL="project (${SETTINGS_FILE})"
fi

banner
echo -e "Scope:     ${YELLOW}${SCOPE_LABEL}${NC}"
echo -e "Bridge:    ${BRIDGE_PATH}"

[ ! -f "${BRIDGE_PATH}" ] && { echo -e "${RED}bridge.sh not found${NC}"; exit 1; }
mkdir -p "${NOTIFY_DIR}/events"

if [ -f "${SETTINGS_FILE}" ] && [ "${FORCE}" != true ]; then
    if grep -q "${VERSION_MARKER}" "${SETTINGS_FILE}" 2>/dev/null; then
        echo -e "${YELLOW}Already installed. Use --force to reinstall.${NC}"
        exit 0
    fi
fi

HOOK_COMMAND="bash ${BRIDGE_PATH} # ${VERSION_MARKER}"

if [ "${DRY_RUN}" = true ]; then
    echo -e "${CYAN}[DRY RUN] Would add Stop hook to ${SETTINGS_FILE}${NC}"
    echo -e "${CYAN}[DRY RUN] Command: ${HOOK_COMMAND}${NC}"
    [ -n "${WEBHOOK_URL}" ] && echo -e "${CYAN}[DRY RUN] Webhook: ${WEBHOOK_URL}${NC}"
    exit 0
fi

mkdir -p "$(dirname "${SETTINGS_FILE}")"

if [ -f "${SETTINGS_FILE}" ]; then
    python3 <<END_PYTHON
import json

with open('${SETTINGS_FILE}') as f:
    try: data = json.load(f)
    except: data = {}

if 'hooks' not in data: data['hooks'] = {}
if 'Stop' not in data['hooks']: data['hooks']['Stop'] = []

already = False
for h in data['hooks']['Stop']:
    for c in h.get('hooks', []):
        if '${VERSION_MARKER}' in c.get('command', ''):
            already = True

if not already:
    data['hooks']['Stop'].append({
        "matcher": "",
        "hooks": [{"type": "command", "command": "${HOOK_COMMAND}", "timeout": 5}]
    })

with open('${SETTINGS_FILE}', 'w') as f:
    json.dump(data, f, indent=2)
    f.write('\n')
END_PYTHON
else
    python3 -c "
import json
d = {'hooks': {'Stop': [{'matcher': '', 'hooks': [{'type': 'command', 'command': '${HOOK_COMMAND}', 'timeout': 5}]}]}}
with open('${SETTINGS_FILE}', 'w') as f:
    json.dump(d, f, indent=2)
    f.write('\n')
"
fi

echo -e "${GREEN}Hook installed.${NC}"

if [ -n "${WEBHOOK_URL}" ]; then
    echo "WEBHOOK_URL=${WEBHOOK_URL}" > "${CONFIG_FILE}"
    echo -e "${GREEN}Webhook configured.${NC}"
fi

echo ""
echo -e "${GREEN}Done!${NC}"
echo -e "  - macOS notifications: immediate"
echo -e "  - Webhook: $([ -f "${CONFIG_FILE}" ] && echo 'configured' || echo 'not set')"
echo -e "  - Chat (Telegram/Discord/Slack): requires Hermes cron setup"
echo ""
echo -e "  Test: echo '{"hook_event_name":"Stop",...}' | bash ${BRIDGE_PATH}"
