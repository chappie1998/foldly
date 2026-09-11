#!/bin/zsh
set -euo pipefail
ROOT="${0:A:h:h}"
OUTPUT="${TMPDIR:-/tmp}/FoldlyGradientTests"
mkdir -p "$ROOT/.build/module-cache"
xcrun swiftc -O -swift-version 5 -module-cache-path "$ROOT/.build/module-cache" \
  -framework CoreImage "$ROOT/Sources/Bendy/BendingModel.swift" \
  "$ROOT/Tests/GradientBlurTests.swift" -o "$OUTPUT"
"$OUTPUT"
