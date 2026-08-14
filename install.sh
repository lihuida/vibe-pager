#!/bin/bash
# 在本机编译并安装到「应用程序」。自己编的包一般不用公证。
set -euo pipefail
ROOT="$(cd "$(dirname "$0")" && pwd)"
APP_NAME="Vibe Pager.app"
DEST="/Applications/$APP_NAME"

echo "正在本机编译 Vibe Pager（只打当前芯片，大约几分钟）…"
"$ROOT/macos/package-app.sh" --native

killall VibePager "Vibe Pager" VibeRemote 2>/dev/null || true
sleep 0.5
rm -rf "$DEST"
ditto --norsrc --noextattr --noacl "$ROOT/dist/$APP_NAME" "$DEST"
xattr -cr "$DEST" 2>/dev/null || true
codesign --force --deep --sign - "$DEST" >/dev/null
/System/Library/Frameworks/CoreServices.framework/Frameworks/LaunchServices.framework/Support/lsregister -f "$DEST" >/dev/null 2>&1 || true

echo "已安装到 $DEST"
open "$DEST" --args --reveal
sleep 1.2

if pgrep -x VibePager >/dev/null 2>&1 || pgrep -x "Vibe Pager" >/dev/null 2>&1; then
  echo
  echo "已启动。请看屏幕右上角菜单栏（时钟左边）的土拨鼠图标，点它打开面板。"
  echo "这是菜单栏应用，Dock 里不会出现图标，这是正常的。"
  echo "如果图标被刘海或其他图标挡住：按住 Command 拖动菜单栏图标腾位置，或打开「应用程序」里的 Vibe Pager。"
else
  echo
  echo "进程没有留下来。请打开「应用程序」，双击 Vibe Pager。"
  echo "若提示已损坏，在终端执行："
  echo "  xattr -cr \"$DEST\""
  open -R "$DEST"
  exit 1
fi
