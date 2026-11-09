#!/bin/bash
set -euo pipefail
repo_root="$(cd "$(dirname "$0")/.." && pwd)"
test_dir="$(mktemp -d "${TMPDIR:-/tmp}/voiceink-length-test.XXXXXX")"
trap 'rm -rf "$test_dir"' EXIT
swiftc -module-cache-path "$test_dir/modules" \
  "$repo_root/VoiceInk/Features/Enhancement/State/EnhancementLengthPolicy.swift" \
  "$repo_root/Tests/EnhancementLengthPolicy/main.swift" \
  -o "$test_dir/threshold-tests"
"$test_dir/threshold-tests"
