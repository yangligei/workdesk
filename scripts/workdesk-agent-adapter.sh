#!/bin/bash
# Generic process adapter: explicitly sends one progress event through the signed local CLI protocol.
# This is not a Hermes/QQ integration and never reads chat or agent logs on its own.
set -euo pipefail
: "${WORKDESK_SOURCE:?set WORKDESK_SOURCE to an enrolled source name}"
: "${WORKDESK_ALIAS:?set WORKDESK_ALIAS to the project alias}"
: "${WORKDESK_TOKEN_FILE:?set WORKDESK_TOKEN_FILE to the 0600 credential file}"
CLI="${WORKDESK_CLI:-/Applications/Workdesk.app/Contents/MacOS/WorkdeskCLI}"
TEXT="${*:-}"
if [[ -z "${TEXT//[[:space:]]/}" ]]; then echo "usage: WORKDESK_SOURCE=... WORKDESK_ALIAS=... WORKDESK_TOKEN_FILE=... $0 TEXT" >&2; exit 2; fi
exec "$CLI" report --source "$WORKDESK_SOURCE" --alias "$WORKDESK_ALIAS" --token-file "$WORKDESK_TOKEN_FILE" --type "${WORKDESK_TYPE:-progress}" --text "$TEXT"
