#!/bin/sh
# 一行安装：curl -fsSL https://raw.githubusercontent.com/ryanmeowy/margin/main/scripts/install.sh | sh
#
# 用 curl 下载的文件不会带 com.apple.quarantine 标记，所以装完第一次打开
# 不会触发 Gatekeeper 的「Apple 无法验证」。这就是终端安装和浏览器下载的区别。
set -e

REPO="ryanmeowy/margin"
ASSET="Margin-v0.1.1-arm64.zip"
TMP="$(mktemp -d)"
trap 'rm -rf "$TMP"' EXIT

echo "→ 下载 $ASSET"
curl -fsSL "https://github.com/$REPO/releases/latest/download/$ASSET" -o "$TMP/margin.zip"

echo "→ 解压"
ditto -x -k "$TMP/margin.zip" "$TMP/out"

echo "→ 安装到 /Applications"
osascript -e 'tell application "Margin" to quit' 2>/dev/null || true
rm -rf "/Applications/Margin.app"
cp -R "$TMP/out/Margin/Margin.app" "/Applications/Margin.app"
xattr -dr com.apple.quarantine "/Applications/Margin.app" 2>/dev/null || true

echo "→ 启动"
open "/Applications/Margin.app"
echo "完成，菜单栏会出现环形图标。"
