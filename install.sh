#!/bin/bash
# 在本机编译并安装到「应用程序」。自己编的包一般不用公证。
set -euo pipefail
ROOT="$(cd "$(dirname "$0")" && pwd)"
APP_NAME="Vibe Pager.app"
DEST="/Applications/$APP_NAME"

echo "正在本机编译 Vibe Pager（只打当前芯片，大约几分钟）…"
"$ROOT/macos/package-app.sh" --native

killall VibePager "Vibe Pager" VibeRemote 2>/dev/null || true
rm -rf "$DEST"
ditto --norsrc --noextattr --noacl "$ROOT/dist/$APP_NAME" "$DEST"
xattr -cr "$DEST" 2>/dev/null || true
codesign --force --deep --sign - "$DEST" >/dev/null

echo "已安装到 $DEST"
open "$DEST"
echo "菜单栏出现土拨鼠图标就成功了。点开面板绑定渠道即可。"
