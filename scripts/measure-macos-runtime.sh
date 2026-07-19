#!/bin/sh
set -eu

PID=${1:-}
DURATION=${2:-300}
INTERVAL=${3:-5}
OUTPUT=${4:-"${TMPDIR:-/tmp}/codex-monitor-hud-runtime.csv"}
case "$PID" in ''|*[!0-9]*) echo "usage: scripts/measure-macos-runtime.sh <pid> [duration-seconds] [interval-seconds] [output.csv]" >&2; exit 2 ;; esac
case "$DURATION:$INTERVAL" in *[!0-9:]*|0:*|*:0) echo "duration and interval must be positive integers" >&2; exit 2 ;; esac
if [ "$(uname -s)" != Darwin ]; then echo "status=unsupported platform=$(uname -s)" >&2; exit 3; fi
if ! kill -0 "$PID" 2>/dev/null; then echo "process not found: $PID" >&2; exit 4; fi

mkdir -p "$(dirname -- "$OUTPUT")"
printf '%s\n' 'timestamp_utc,rss_kb,vsz_kb,cpu_percent,fd_count' > "$OUTPUT"
ELAPSED=0
while [ "$ELAPSED" -le "$DURATION" ] && kill -0 "$PID" 2>/dev/null; do
  set -- $(ps -p "$PID" -o rss= -o vsz= -o %cpu=)
  RSS=${1:-0}
  VSZ=${2:-0}
  CPU=${3:-0}
  FD_COUNT=$(lsof -n -P -p "$PID" 2>/dev/null | awk 'NR > 1 { count++ } END { print count + 0 }')
  printf '%s,%s,%s,%s,%s\n' "$(date -u '+%Y-%m-%dT%H:%M:%SZ')" "$RSS" "$VSZ" "$CPU" "$FD_COUNT" >> "$OUTPUT"
  if [ "$ELAPSED" -eq "$DURATION" ]; then break; fi
  sleep "$INTERVAL"
  ELAPSED=$((ELAPSED + INTERVAL))
done

printf '%s\n' "status=ok output=$OUTPUT samples=$(($(wc -l < "$OUTPUT") - 1))"
