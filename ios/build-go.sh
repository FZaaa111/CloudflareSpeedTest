#!/usr/bin/env bash
# 使用 gomobile 将 Go 测速核心（../mobile）编译为 iOS xcframework
# 需要：macOS + Xcode + Go 1.21+
set -euo pipefail

IOS_DIR="$(cd "$(dirname "$0")" && pwd)"
ROOT_DIR="$(cd "$IOS_DIR/.." && pwd)"
OUT="$IOS_DIR/Frameworks/Cfst.xcframework"

export PATH="$PATH:$(go env GOPATH)/bin"

if ! command -v gomobile >/dev/null 2>&1; then
	echo "安装 gomobile..."
	go install golang.org/x/mobile/cmd/gomobile@latest
	go install golang.org/x/mobile/cmd/gobind@latest
fi
gomobile init

cd "$ROOT_DIR"
# gomobile bind 需要在 go.mod 中依赖 golang.org/x/mobile，构建完成后还原 go.mod / go.sum，避免影响命令行版本
cp go.mod "$IOS_DIR/.go.mod.bak"
cp go.sum "$IOS_DIR/.go.sum.bak"
restore() {
	mv "$IOS_DIR/.go.mod.bak" go.mod
	mv "$IOS_DIR/.go.sum.bak" go.sum
}
trap restore EXIT

go get golang.org/x/mobile/bind
mkdir -p "$IOS_DIR/Frameworks"
rm -rf "$OUT"
gomobile bind -target=ios,iossimulator -iosversion=16.0 -ldflags="-s -w" -o "$OUT" ./mobile
echo "已生成 $OUT"
