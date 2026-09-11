#!/bin/zsh
set -euo pipefail

SCRIPT_DIR="${0:A:h}"
APP="$SCRIPT_DIR/build/Foldly.app"
CACHE="$SCRIPT_DIR/.build/module-cache"

mkdir -p "$APP/Contents/MacOS" "$APP/Contents/Resources" "$CACHE" "$SCRIPT_DIR/../public"
cp "$SCRIPT_DIR/Info.plist" "$APP/Contents/Info.plist"
cp "$SCRIPT_DIR/Resources/fold-finish.wav" "$APP/Contents/Resources/fold-finish.wav"

xcrun swiftc \
  -swift-version 5 \
  -target arm64-apple-macosx14.0 \
  -module-cache-path "$CACHE" \
  -O \
  -framework AppKit -framework SwiftUI -framework Combine \
  -framework ScreenCaptureKit -framework CoreImage -framework CoreMedia -framework CoreVideo \
  -framework Metal -framework MetalKit -framework IOKit \
  "$SCRIPT_DIR"/Sources/Bendy/*.swift \
  -o "$APP/Contents/MacOS/Foldly"

codesign --force --sign - "$APP"
ditto -c -k --keepParent "$APP" "$SCRIPT_DIR/../public/Foldly.zip"
echo "Built $APP"
echo "Packaged $SCRIPT_DIR/../public/Foldly.zip"
