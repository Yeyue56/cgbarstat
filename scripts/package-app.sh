#!/bin/bash
set -euo pipefail
cd "$(dirname "$0")/.."
swift build -c release
BIN_DIR="$(swift build -c release --show-bin-path)"
rm -rf CGBarStat.app
mkdir -p CGBarStat.app/Contents/MacOS CGBarStat.app/Contents/Resources
cp "$BIN_DIR/CGBarStatApp" CGBarStat.app/Contents/MacOS/CGBarStatApp
cp Support/Info.plist CGBarStat.app/Contents/Info.plist
cp Support/AppIcon.icns CGBarStat.app/Contents/Resources/AppIcon.icns
chmod +x CGBarStat.app/Contents/MacOS/CGBarStatApp
