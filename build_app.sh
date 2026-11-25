#!/bin/zsh
set -euo pipefail

PROJECT_DIR="/Users/hyg/Desktop/project/chiikawa-desktop"
APP_BUNDLE="$PROJECT_DIR/ChiikawaDesktop.app"

echo "🔨 Compiling ChiikawaDesktop (Release -O)..."
swiftc \
  -module-cache-path /tmp/swift-module-cache \
  -target arm64-apple-macosx14.0 \
  -O \
  "$PROJECT_DIR"/Sources/ChiikawaDesktop/*.swift \
  -o "$PROJECT_DIR/ChiikawaDesktop"

mkdir -p "$APP_BUNDLE/Contents/MacOS"
mkdir -p "$APP_BUNDLE/Contents/Resources"

cp "$PROJECT_DIR/ChiikawaDesktop" "$APP_BUNDLE/Contents/MacOS/ChiikawaDesktop"
rm -rf "$APP_BUNDLE/Contents/Resources/spec" "$APP_BUNDLE/Contents/Resources/assets"
cp -R "$PROJECT_DIR/spec" "$APP_BUNDLE/Contents/Resources/spec"
cp -R "$PROJECT_DIR/assets" "$APP_BUNDLE/Contents/Resources/assets"

cat > "$APP_BUNDLE/Contents/Info.plist" <<EOF
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
    <key>CFBundleExecutable</key>
    <string>ChiikawaDesktop</string>
    <key>CFBundleIdentifier</key>
    <string>com.chiikawa.desktop</string>
    <key>CFBundleName</key>
    <string>ChiikawaDesktop</string>
    <key>CFBundlePackageType</key>
    <string>APPL</string>
    <key>CFBundleShortVersionString</key>
    <string>1.5.1</string>
    <key>LSUIElement</key>
    <true/>
    <key>NSHighResolutionCapable</key>
    <true/>
</dict>
</plist>
EOF

# Remove extended quarantine/provenance attributes and apply a stable ad-hoc code signature
xattr -cr "$APP_BUNDLE" 2>/dev/null || true
codesign --force --deep --sign - --identifier "com.chiikawa.desktop" "$APP_BUNDLE" 2>/dev/null || true

echo "✅ Built $APP_BUNDLE and $PROJECT_DIR/ChiikawaDesktop"
