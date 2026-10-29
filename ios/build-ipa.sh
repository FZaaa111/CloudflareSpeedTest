#!/usr/bin/env bash
# 编译未签名的 dist/CFST.ipa，可用 Sideloadly / AltStore / SideStore / TrollStore 安装（安装时由这些工具签名）
# 需要：macOS + Xcode + XcodeGen
set -euo pipefail

IOS_DIR="$(cd "$(dirname "$0")" && pwd)"
cd "$IOS_DIR"

if ! xcrun xcodebuild -version >/dev/null 2>&1; then
	echo "错误：未找到 Xcode（当前开发者目录：$(xcode-select -p 2>/dev/null || echo 未设置)）。" >&2
	echo "请从 App Store 安装 Xcode 并至少打开一次，然后执行：" >&2
	echo "  sudo xcode-select -s /Applications/Xcode.app/Contents/Developer" >&2
	exit 1
fi

if [ ! -d Frameworks/Cfst.xcframework ]; then
	./build-go.sh
fi
if [ ! -d CFST.xcodeproj ]; then
	xcodegen
fi

rm -rf build dist
xcodebuild \
	-project CFST.xcodeproj \
	-scheme CFST \
	-configuration Release \
	-sdk iphoneos \
	-destination 'generic/platform=iOS' \
	-derivedDataPath build \
	CODE_SIGNING_ALLOWED=NO \
	CODE_SIGNING_REQUIRED=NO \
	CODE_SIGN_IDENTITY="" \
	build

APP="build/Build/Products/Release-iphoneos/CFST.app"
if [ ! -d "$APP" ]; then
	echo "错误：未找到 $APP" >&2
	exit 1
fi

mkdir -p dist/Payload
cp -R "$APP" dist/Payload/
(cd dist && zip -qry CFST.ipa Payload && rm -rf Payload)
echo "已生成 $IOS_DIR/dist/CFST.ipa（未签名）"
