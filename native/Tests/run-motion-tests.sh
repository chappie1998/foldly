#!/bin/zsh
set -euo pipefail
ROOT="${0:A:h:h}"
OUTPUT="${TMPDIR:-/tmp}/FoldlyMotionTests"
mkdir -p "$ROOT/.build/module-cache"
xcrun swiftc -O -swift-version 5 -module-cache-path "$ROOT/.build/module-cache" \
  -framework AppKit -framework Combine -framework CoreImage "$ROOT/Sources/Bendy/BendingModel.swift" \
  "$ROOT/Sources/Bendy/AppSettings.swift" \
  "$ROOT/Sources/Bendy/SystemPromptMonitor.swift" \
  "$ROOT/Sources/Bendy/CaptureLifecycle.swift" "$ROOT/Tests/MotionPolicyTests.swift" -o "$OUTPUT"
"$OUTPUT"
