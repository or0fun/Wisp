#!/bin/bash
set -euo pipefail
project_root="$(cd "$(dirname "$0")/.." && pwd)"
cache="$project_root/.build/module-cache"
output="$project_root/.build/checks/input-synchronization"
mkdir -p "$cache" "$(dirname "$output")"
sources=()
for source in "$project_root"/Sources/Wisp/*.swift "$project_root"/Sources/Wisp/UI/*.swift; do
    if [[ "${source##*/}" != "WispApp.swift" ]]; then
        sources+=("$source")
    fi
done
# Standalone AppKit regression checks also run with Command Line Tools only.
swiftc -parse-as-library -module-cache-path "$cache" "${sources[@]}" \
    "$project_root/Tests/InputSynchronizationChecks.swift" -o "$output" \
    -framework AppKit -framework Carbon -framework Security -framework ServiceManagement
"$output"
