#!/usr/bin/env bash
set -euo pipefail

mode="${1:-fast}"
if [[ "$mode" != "fast" && "$mode" != "full" ]]; then
  echo "usage: $0 [fast|full]" >&2
  exit 2
fi

root_dir="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
cd "$root_dir"

ts="$(date -u +%Y%m%d-%H%M%S)"
out_dir="artifacts/qa/${ts}"
mkdir -p "$out_dir"

summary="$out_dir/summary.txt"
commands_log="$out_dir/commands.log"

printf 'LLMAB QA run\nmode: %s\nutc: %s\noutput: %s\n\n' "$mode" "$(date -u)" "$out_dir" | tee "$summary"

run_step() {
  local name="$1"
  local log_file="$2"
  shift 2

  echo "==> $name" | tee -a "$commands_log" "$summary"
  echo "cmd: $*" | tee -a "$commands_log"

  if "$@" >"$log_file" 2>&1; then
    echo "PASS: $name" | tee -a "$summary"
  else
    echo "FAIL: $name" | tee -a "$summary"
    echo "see log: $log_file" | tee -a "$summary"
    exit 1
  fi

  echo >>"$summary"
}

run_step "swift build" "$out_dir/build.log" swift build -c debug
run_step "swift test" "$out_dir/test.log" swift test --parallel
run_step "strip macOS metadata" "$out_dir/xattr.log" ./scripts/normalize-macos-metadata.sh
run_step "xcodegen" "$out_dir/xcodegen.log" xcodegen generate
run_step "xcodebuild debug app" "$out_dir/xcodebuild.log" \
  xcodebuild -project LLMAB.xcodeproj \
             -scheme LLMABApp \
             -configuration Debug \
             -derivedDataPath build/DerivedData \
             build

if [[ "$mode" == "full" ]]; then
  {
    echo "MANUAL CHECKLIST REQUIRED"
    echo "- Open docs/TEST-CHECKLIST.md"
    echo "- Execute runtime matrix and permission matrix from docs/QA-PLAN.md"
    echo "- Attach evidence (screenshots/logs) for any failures"
  } | tee "$out_dir/manual-checklist.txt" >>"$summary"
fi

echo "QA completed successfully." | tee -a "$summary"
