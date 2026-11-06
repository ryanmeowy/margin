#!/bin/bash
# 只用 Command Line Tools 手工拼 .app。用法: ./build.sh
set -euo pipefail
cd "$(dirname "$0")"
APP=build/CoRouterSpike.app
rm -rf "$APP"
mkdir -p "$APP/Contents/MacOS" "$APP/Contents/Resources"
cp Info.plist "$APP/Contents/Info.plist"
cp web/panel.html "$APP/Contents/Resources/panel.html"
swiftc -O main.swift -o "$APP/Contents/MacOS/CoRouterSpike" -framework AppKit -framework WebKit
codesign --force --deep --sign - "$APP"
codesign --verify --verbose=1 "$APP" 2>&1 | tail -2
echo "size: $(du -sk "$APP" | cut -f1) KB"
