#!/bin/bash
# 构建 dist/EchoType.app（临时本地签名；正式分发需 Developer ID 签名 + 公证）
set -euo pipefail
cd "$(dirname "$0")/.."

CONFIG="release"
if [ "${1:-release}" = "debug" ]; then CONFIG="debug"; fi

# Liquid Glass 由链接时记录的 SDK 版本门控：LC_BUILD_VERSION 的 sdk 字段可能写成
# 部署目标（13.0），macOS 会因此把 NSGlassEffectView 降级为普通视图。
# 这里保持 minos=13.0（与 Package.swift 的 platforms: [.macOS(.v13)] 一致，两者要同步改），
# 但如实声明实际编译所用的 SDK 版本。
SDK_VERSION="$(xcrun --show-sdk-version)"
swift build -c "$CONFIG" \
    -Xlinker -platform_version -Xlinker macos -Xlinker 13.0 -Xlinker "$SDK_VERSION"

APP="dist/EchoType.app"
BIN=".build/$CONFIG/EchoType"
rm -rf "$APP"
mkdir -p "$APP/Contents/MacOS" "$APP/Contents/Resources"
cp "Resources/AppIcon.icns" "$APP/Contents/Resources/AppIcon.icns"

cat > "$APP/Contents/Info.plist" <<'PLIST'
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
    <key>CFBundleName</key><string>EchoType</string>
    <key>CFBundleDisplayName</key><string>EchoType</string>
    <key>CFBundleIdentifier</key><string>com.echotype.app</string>
    <key>CFBundleVersion</key><string>0.4.0</string>
    <key>CFBundleShortVersionString</key><string>0.4.0</string>
    <key>CFBundleExecutable</key><string>EchoType</string>
    <key>CFBundleIconFile</key><string>AppIcon</string>
    <key>CFBundlePackageType</key><string>APPL</string>
    <key>CFBundleDevelopmentRegion</key><string>zh_CN</string>
    <key>LSMinimumSystemVersion</key><string>13.0</string>
    <key>NSHighResolutionCapable</key><true/>
    <key>NSPrincipalClass</key><string>NSApplication</string>
    <key>LSUIElement</key><true/>
</dict>
</plist>
PLIST

cp "$BIN" "$APP/Contents/MacOS/EchoType"
# 固定 bundle id + 指定需求（DR），让 TCC 辅助功能授权在重新构建后依然有效
codesign --force --sign - --identifier com.echotype.app \
    --requirements '=designated => identifier "com.echotype.app"' "$APP"
echo "打包完成：$APP"
