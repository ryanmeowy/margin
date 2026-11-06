#!/bin/sh
# 双击运行：把 Margin.app 复制到「应用程序」并去掉下载隔离标记，然后打开。
# 这是未签名 App 在 macOS 上的标准绕过方式，脚本只做三件事，可以自己看一眼。
set -e
cd "$(dirname "$0")"

TARGET="/Applications/Margin.app"

if [ -d "$TARGET" ]; then
  echo "发现已安装的 Margin，先退出旧版本…"
  osascript -e 'tell application "Margin" to quit' 2>/dev/null || true
  rm -rf "$TARGET"
fi

if [ -d "./Margin.app" ]; then
  echo "复制到 /Applications …"
  cp -R "./Margin.app" "$TARGET"
else
  echo "没找到 Margin.app，请确认它和本脚本在同一个文件夹里。"
  read -r -p "按回车退出…" _
  exit 1
fi

echo "移除下载隔离标记…"
xattr -dr com.apple.quarantine "$TARGET" 2>/dev/null || true

echo "启动 Margin…"
open "$TARGET"
echo "完成。菜单栏会出现环形图标。"
sleep 1
