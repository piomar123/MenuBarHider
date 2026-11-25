#!/bin/bash
# Runs the unit tests without Xcode (Command Line Tools have no XCTest): compiles the app sources,
# the test files and a minimal XCTest stand-in into one executable and runs every test method.
# ApplicationRelaunchTests is skipped: it needs XCTest expectations. Usage: tools/xctest-shim/run.sh
set -euo pipefail
D="$(cd "$(dirname "$0")" && pwd)"
R="$(cd "$D/../.." && pwd)"
W="$R/build-xctest"
rm -rf "$W"; mkdir -p "$W/src"
for f in "$R"/MenuBarHiderTests/*.swift; do
  [[ "$(basename "$f")" == ApplicationRelaunchTests.swift ]] && continue
  sed -e 's/^@testable import MenuBarHider//' -e 's/^import XCTest/import Foundation/' "$f" > "$W/src/$(basename "$f")"
done
python3 "$D/gen_main.py" "$W/main.swift" "$W"/src/*Tests.swift
xcrun swiftc -swift-version 5 -module-name Runner -sdk "$(xcrun --sdk macosx --show-sdk-path)" \
  -target arm64-apple-macos27.0 -framework AppKit -framework ApplicationServices -framework ServiceManagement \
  $(find "$R/MenuBarHider" -name '*.swift' ! -name main.swift | sort) "$W"/src/*.swift "$D/XCTestShim.swift" \
  "$W/main.swift" -o "$W/runner"
echo "Running $(grep -c 'xctCurrent =' "$W/main.swift") tests"
"$W/runner"
