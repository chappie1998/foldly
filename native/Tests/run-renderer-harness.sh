#!/bin/zsh
set -euo pipefail

ROOT="${0:A:h:h}"
OUTPUT="${TMPDIR:-/tmp}/FoldlyRendererFramebufferHarness"
CACHE="$ROOT/.build/module-cache"

mkdir -p "$CACHE"
xcrun swiftc \
  -O -D RENDERER_TEST \
  -swift-version 5 \
  -target arm64-apple-macosx14.0 \
  -module-cache-path "$CACHE" \
  -framework AppKit -framework CoreImage -framework CoreVideo \
  -framework Metal -framework MetalKit \
  "$ROOT/Sources/Bendy/BendingModel.swift" \
  "$ROOT/Sources/Bendy/MetalOverlayView.swift" \
  "$ROOT/Tests/RendererFramebufferHarness.swift" \
  -o "$OUTPUT"

"$OUTPUT" "$@"
