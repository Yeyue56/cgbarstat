#!/bin/bash
set -euo pipefail
cd "$(dirname "$0")/.."
swift build -c release
BIN_DIR="$(swift build -c release --show-bin-path)"
rm -rf Stipend.app
mkdir -p Stipend.app/Contents/MacOS Stipend.app/Contents/Resources
cp "$BIN_DIR/StipendApp" Stipend.app/Contents/MacOS/StipendApp
cp Support/Info.plist Stipend.app/Contents/Info.plist
cp Support/AppIcon.icns Stipend.app/Contents/Resources/AppIcon.icns
chmod +x Stipend.app/Contents/MacOS/StipendApp
