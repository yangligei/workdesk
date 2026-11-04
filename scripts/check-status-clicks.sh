#!/bin/bash
# Status-bar click regression: drives the real NSStatusBarWindow with real
# NSEvents against synthetic scratch data. Never touches the user's data.
set -uo pipefail
cd "$(dirname "$0")/.."
APP="${1:-.build/debug/Workdesk}"
DATA="$(mktemp -d "${TMPDIR:-/tmp}/workdesk-status-XXXXXX")"
trap 'rm -rf "$DATA"' EXIT
export WORKDESK_DATA_DIR="$DATA" WORKDESK_DISABLE_NOTIFICATIONS=1

status=0
for mode in --check-status-clicks --check-status-menu --check-status-cg; do
  echo "--- $mode"
  "$APP" "$mode"
  code=$?
  if [ "$code" -eq 3 ]; then
    echo "SKIP: $mode (Accessibility permission unavailable; verify with a real double click)"
    continue
  fi
  if [ "$code" -ne 0 ]; then status=1; fi
done
exit "$status"
