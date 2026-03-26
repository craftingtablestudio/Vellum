#!/bin/bash
set -e

echo "Running tests with coverage..."
swift test --enable-code-coverage

BIN_DIR=$(swift build --show-bin-path)
BUNDLE=$(find "$BIN_DIR" -maxdepth 1 -name "*.xctest" -type d | head -1)
BINARY="$BUNDLE/Contents/MacOS/$(basename "$BUNDLE" .xctest)"

echo "Coverage report:"
xcrun llvm-cov report \
  "$BINARY" \
  -instr-profile "$BIN_DIR/codecov/default.profdata" \
  --ignore-filename-regex=".build|Tests"
