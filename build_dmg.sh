#!/bin/bash
# 将 Logpad 构建为 Release 版本并打包成 DMG（ad-hoc 签名，供内部测试）。
# 用法：./build_dmg.sh
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "$0")" && pwd)"
PROJECT_DIR="$ROOT_DIR/Logpad"
SCHEME="Logpad"
APP_NAME="Logpad"
BUILD_DIR="$ROOT_DIR/build"
DERIVED="$BUILD_DIR/DerivedData"

cd "$PROJECT_DIR"

VERSION=$(xcodebuild -project Logpad.xcodeproj -scheme "$SCHEME" -configuration Release -showBuildSettings 2>/dev/null \
  | awk -F' = ' '/ MARKETING_VERSION =/{print $2; exit}')
VERSION=${VERSION:-dev}

echo "==> 构建 $APP_NAME $VERSION (Release)…"
rm -rf "$BUILD_DIR"
xcodebuild \
  -project Logpad.xcodeproj \
  -scheme "$SCHEME" \
  -configuration Release \
  -derivedDataPath "$DERIVED" \
  clean build | tail -5

APP_PATH="$DERIVED/Build/Products/Release/$APP_NAME.app"
[ -d "$APP_PATH" ] || { echo "构建产物不存在: $APP_PATH"; exit 1; }

echo "==> 组织 DMG 内容…"
STAGING="$BUILD_DIR/dmg"
mkdir -p "$STAGING"
cp -R "$APP_PATH" "$STAGING/"
ln -s /Applications "$STAGING/Applications"

DMG_PATH="$BUILD_DIR/${APP_NAME}-${VERSION}.dmg"
echo "==> 生成 $DMG_PATH …"
hdiutil create \
  -volname "$APP_NAME $VERSION" \
  -srcfolder "$STAGING" \
  -fs HFS+ \
  -format UDZO \
  -ov \
  "$DMG_PATH"

echo ""
echo "✅ 完成: $DMG_PATH"
echo "   把它发给测试者，拖入 Applications 即可安装。"
