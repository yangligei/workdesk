#!/bin/bash
set -euo pipefail
cd "$(dirname "$0")/.."
swift build -c release
APP="$PWD/dist/Workdesk.app"
mkdir -p "$APP/Contents/MacOS"
cp .build/release/Workdesk "$APP/Contents/MacOS/Workdesk"
cp resources/Info.plist "$APP/Contents/Info.plist"
codesign --force --sign - "$APP"
printf '%s\n' "$APP"
