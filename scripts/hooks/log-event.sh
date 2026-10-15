#!/usr/bin/env bash
# Copilot hook (Linux/macOS, cloud agent): appends a lifecycle event to .sdd/telemetry/events.jsonl.
# Mirrors scripts/hooks/log-event.ps1. Never fails the agent: always exits 0.
event="${1:-unknown}"
payload="$(cat 2>/dev/null)"
[ -z "$payload" ] && payload="null"
dir=".sdd/telemetry"
mkdir -p "$dir" 2>/dev/null
branch="$(git branch --show-current 2>/dev/null)"
ts="$(date -u +%Y-%m-%dT%H:%M:%S.%3NZ 2>/dev/null || date -u +%Y-%m-%dT%H:%M:%SZ)"
printf '{"ts":"%s","event":"%s","branch":"%s","change_id":"%s","phase":"%s","payload":%s}\n' \
  "$ts" "$event" "$branch" "${SDD_CHANGE_ID:-}" "${SDD_PHASE:-}" "$payload" >> "$dir/events.jsonl" 2>/dev/null
exit 0
