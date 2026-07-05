#!/usr/bin/env bash
# fm-session-digest.sh — compact one-line-per-task summary of all tracked crew.
# Use at session start in place of reading state/*.meta and state/*.status
# individually. Outputs one tab-separated line per task and exits 0.
#
# Line format (tab-separated, missing fields printed as "-"):
#   <id>  <kind>  <project>/<mode>  <window>  <last-status-line>
#
# Silent when no tasks are in flight. Never fails the caller on a read error.
set -u

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
FM_ROOT="${FM_ROOT_OVERRIDE:-$(cd "$SCRIPT_DIR/.." && pwd)}"
FM_HOME="${FM_HOME:-${FM_ROOT_OVERRIDE:-$FM_ROOT}}"
STATE="${FM_STATE_OVERRIDE:-$FM_HOME/state}"

for meta in "$STATE"/*.meta; do
  [ -e "$meta" ] || continue
  id=$(basename "$meta" .meta)
  kind=$(grep '^kind='    "$meta" 2>/dev/null | tail -1 | cut -d= -f2-); kind=${kind:-ship}
  project=$(grep '^project=' "$meta" 2>/dev/null | tail -1 | cut -d= -f2-); project=${project:--}
  mode=$(grep '^mode='    "$meta" 2>/dev/null | tail -1 | cut -d= -f2-); mode=${mode:--}
  window=$(grep '^window=' "$meta" 2>/dev/null | tail -1 | cut -d= -f2-); window=${window:--}
  last_status="-"
  if [ -f "$STATE/$id.status" ]; then
    line=$(grep -v '^[[:space:]]*$' "$STATE/$id.status" 2>/dev/null | tail -1 || true)
    [ -n "$line" ] && last_status="$line"
  fi
  printf '%s\t%s\t%s/%s\t%s\t%s\n' "$id" "$kind" "$project" "$mode" "$window" "$last_status"
done
