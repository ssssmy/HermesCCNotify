#!/usr/bin/env bash
# ============================================================
# HermesCCNotify uninstall.sh
# Removes the Stop hook from Claude Code settings.
# ============================================================
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
BRIDGE_PATH="${SCRIPT_DIR}/bridge.sh"
VERSION_MARKER="hermesccnotify-v1"
RED='\033[0;31m'; GREEN='\033[0;32m'; YELLOW='\033[1;33m'; NC='\033[0m'

SCOPE="global"; PROJECT_DIR=""; FORCE=false

while [[ $# -gt 0 ]]; do
    case "$1" in
        --global) SCOPE="global"; shift ;;
        --project) PROJECT_DIR="$2"; SCOPE="project"; shift 2 ;;
        --force) FORCE=true; shift ;;
        -h|--help)
            echo "Usage: uninstall.sh [--global] [--project DIR]"
            echo "Removes HermesCCNotify hook from Claude Code settings."
            exit 0 ;;
        *) echo -e "${RED}Unknown: $1${NC}"; exit 1 ;;
    esac
done

if [ "${SCOPE}" = "global" ]; then
    SETTINGS_FILE="${HOME}/.claude/settings.json"
else
    [ -z "${PROJECT_DIR}" ] && { echo -e "${RED}--project requires a directory${NC}"; exit 1; }
    SETTINGS_FILE="${PROJECT_DIR}/.claude/settings.json"
fi

if [ ! -f "${SETTINGS_FILE}" ]; then
    echo -e "${YELLOW}No settings file at ${SETTINGS_FILE}${NC}"
    exit 0
fi

python3 <<END_PYTHON
import json

with open('${SETTINGS_FILE}') as f:
    data = json.load(f)

removed = 0
if 'hooks' in data and 'Stop' in data['hooks']:
    new_stop = []
    for entry in data['hooks']['Stop']:
        kept = [c for c in entry.get('hooks', []) if '${VERSION_MARKER}' not in c.get('command', '')]
        if kept:
            entry['hooks'] = kept
            new_stop.append(entry)
        else:
            removed += len(entry.get('hooks', []))
    if new_stop:
        data['hooks']['Stop'] = new_stop
    else:
        del data['hooks']['Stop']
    if not data['hooks']:
        del data['hooks']

with open('${SETTINGS_FILE}', 'w') as f:
    json.dump(data, f, indent=2)
    f.write('\\n')

print(f'Removed {removed} hook entries')
END_PYTHON

echo -e "${GREEN}Uninstalled from ${SETTINGS_FILE}${NC}"

# Clean up runtime files
rm -rf "${HOME}/.hermesccnotify"
echo -e "${GREEN}Cleaned up ~/.hermesccnotify/${NC}"
