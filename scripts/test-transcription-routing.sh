#!/bin/bash
set -euo pipefail
repo_root="$(cd "$(dirname "$0")/.." && pwd)"
test_dir="$(mktemp -d "${TMPDIR:-/tmp}/voiceink-routing-test.XXXXXX")"
trap 'rm -rf "$test_dir"' EXIT
swiftc -parse-as-library -module-cache-path "$test_dir/modules" \
  "$repo_root/VoiceInk/Features/Modes/State/TranscriptionLengthRoute.swift" \
  "$repo_root/VoiceInk/Features/Recording/Workflows/TranscriptionLengthRouter.swift" \
  "$repo_root/Tests/TranscriptionLengthRouting/main.swift" \
  -o "$test_dir/routing-tests"
"$test_dir/routing-tests"
