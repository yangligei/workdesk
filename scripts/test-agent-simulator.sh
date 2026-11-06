#!/bin/bash
# Local end-to-end simulator. Uses only a temporary WORKDESK_DATA_DIR; never touches the user's app data.
# This validates the generic adapter and CLI protocol. It is not a real Hermes/QQ connection.
set -euo pipefail
ROOT="$(cd "$(dirname "$0")/.." && pwd)"
TMP="$(mktemp -d "${TMPDIR:-/tmp}/workdesk-simulator.XXXXXX")"
trap 'rm -rf "$TMP"' EXIT
export WORKDESK_DATA_DIR="$TMP/data"
export WORKDESK_CLI="$ROOT/.build/release/WorkdeskCLI"
export WORKDESK_TOKEN_FILE="$TMP/simulator.key"
export WORKDESK_SOURCE="local-simulator"
export WORKDESK_ALIAS="fixture-project"
"$WORKDESK_CLI" enroll --name "$WORKDESK_SOURCE" --token-file "$WORKDESK_TOKEN_FILE" >/dev/null
"$WORKDESK_CLI" report --source "$WORKDESK_SOURCE" --alias "$WORKDESK_ALIAS" --token-file "$WORKDESK_TOKEN_FILE" --type project.create --event-id denied --text "默认拒绝" >/dev/null
"$WORKDESK_CLI" drain >/dev/null
[[ "$(sqlite3 "$WORKDESK_DATA_DIR/workdesk.sqlite" "SELECT count(*) FROM projects;")" == "0" ]]
"$WORKDESK_CLI" grant-create --name "$WORKDESK_SOURCE" --allow yes >/dev/null
for repeat in 1 2; do
 "$WORKDESK_CLI" report --source "$WORKDESK_SOURCE" --alias "$WORKDESK_ALIAS" --token-file "$WORKDESK_TOKEN_FILE" --type project.create --event-id create-001 --text "隔离模拟项目" >/dev/null
 "$WORKDESK_CLI" drain >/dev/null
done
[[ "$(sqlite3 "$WORKDESK_DATA_DIR/workdesk.sqlite" "SELECT count(*) FROM projects;")" == "1" ]]
[[ "$(stat -f '%Lp' "$WORKDESK_TOKEN_FILE")" == "600" ]] || { echo "FAIL: credential permissions"; exit 1; }
"$ROOT/scripts/workdesk-agent-adapter.sh" "本地模拟器：完成一步检查"
"$WORKDESK_CLI" report --source "$WORKDESK_SOURCE" --alias "$WORKDESK_ALIAS" --token-file "$WORKDESK_TOKEN_FILE" --type task.create --text "模拟器创建的任务" >/dev/null
"$WORKDESK_CLI" drain
[[ "$(sqlite3 "$WORKDESK_DATA_DIR/workdesk.sqlite" "SELECT count(*) FROM tasks WHERE title='模拟器创建的任务';")" == "1" ]] || { echo "FAIL: signed task not stored"; exit 1; }
[[ "$(sqlite3 "$WORKDESK_DATA_DIR/workdesk.sqlite" "SELECT count(*) FROM events WHERE outcome='accepted';")" == "3" ]] || { echo "FAIL: accepted audit count"; exit 1; }
echo "PASS: 本地隔离模拟器（非真实外部智能体）；签名上报、项目范围、去重与审计可验证"
