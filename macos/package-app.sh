#!/bin/bash
set -euo pipefail
ROOT="$(cd "$(dirname "$0")/.." && pwd)"
APP_DIR="$ROOT/dist/Vibe Pager.app"
BIN_DIR="$APP_DIR/Contents/MacOS"
RES_DIR="$APP_DIR/Contents/Resources"
BUILD="$ROOT/macos/.build"
OUT="$BUILD/VibePager"

if [[ -z "${SDK:-}" ]]; then
  if [[ -d /Library/Developer/CommandLineTools/SDKs/MacOSX.sdk ]]; then
    SDK=/Library/Developer/CommandLineTools/SDKs/MacOSX.sdk
  elif command -v xcrun >/dev/null 2>&1; then
    SDK="$(xcrun --show-sdk-path 2>/dev/null || true)"
  fi
fi
if [[ -z "${SDK:-}" || ! -d "$SDK" ]]; then
  echo "找不到 macOS SDK。请先安装编译工具："
  echo "  xcode-select --install"
  exit 1
fi
if ! command -v swiftc >/dev/null 2>&1; then
  echo "找不到 swiftc。请先安装编译工具："
  echo "  xcode-select --install"
  exit 1
fi

native_arch() {
  if [[ "$(sysctl -n hw.optional.arm64 2>/dev/null || true)" == "1" ]]; then
    echo arm64
  else
    echo x86_64
  fi
}

if [[ "${1:-}" == "--native" ]]; then
  ARCHS=("$(native_arch)")
else
  ARCHS=(x86_64 arm64)
fi

mkdir -p "$BUILD"

compile() {
  local arch="$1"
  local dest="$2"
  echo "compiling $arch…"
  swiftc -sdk "$SDK" \
    -target "${arch}-apple-macosx13.0" \
    -parse-as-library \
    -framework SwiftUI -framework AppKit -framework CryptoKit -framework Network -framework CoreGraphics -framework ApplicationServices -framework CoreImage \
    -O \
    -o "$dest" \
    "$ROOT"/macos/Sources/VibeRemote/*.swift
}

SLICES=()
for arch in "${ARCHS[@]}"; do
  dest="$BUILD/VibePager-$arch"
  compile "$arch" "$dest"
  SLICES+=("$dest")
done

if [[ ${#SLICES[@]} -eq 1 ]]; then
  cp "${SLICES[0]}" "$OUT"
else
  lipo -create "${SLICES[@]}" -output "$OUT"
fi
lipo -info "$OUT"

rm -rf "$APP_DIR" "$ROOT/dist/VibeRemote.app"
mkdir -p "$BIN_DIR" "$RES_DIR"
cp "$OUT" "$BIN_DIR/VibePager"
cp "$ROOT/macos/Info.plist" "$APP_DIR/Contents/Info.plist"

if [[ -f "$ROOT/macos/Resources/AppIcon.icns" ]]; then
  cp "$ROOT/macos/Resources/AppIcon.icns" "$RES_DIR/AppIcon.icns"
fi
if [[ -f "$ROOT/macos/Resources/StatusItem@2x.png" ]]; then
  cp "$ROOT/macos/Resources/StatusItem@2x.png" "$RES_DIR/StatusItem@2x.png"
fi
if [[ -f "$ROOT/macos/Resources/StatusItem.png" ]]; then
  cp "$ROOT/macos/Resources/StatusItem.png" "$RES_DIR/StatusItem.png"
fi
if compgen -G "$ROOT/macos/Resources/brands/brand-*.png" > /dev/null; then
  cp "$ROOT"/macos/Resources/brands/brand-*.png "$RES_DIR/"
fi

# 苹果芯片要求可执行文件至少有临时签名，否则会提示无法打开 / 已损坏。
codesign --force --deep --sign - "$APP_DIR"

if [[ "${1:-}" != "--native" ]]; then
  ZIP="$ROOT/dist/Vibe-Pager-universal.zip"
  rm -f "$ZIP"
  ditto -c -k --keepParent --norsrc --noextattr --noacl "$APP_DIR" "$ZIP"
  echo "zip    $ZIP"
fi

/System/Library/Frameworks/CoreServices.framework/Frameworks/LaunchServices.framework/Support/lsregister -f "$APP_DIR" >/dev/null 2>&1 || true

echo "built $APP_DIR"
