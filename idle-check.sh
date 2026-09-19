#!/bin/bash
# idle-check.sh — returns idle time in seconds for auto-dim.
# Reads the activity timestamp written by idle-tracker.sh.
# Returns 0 when no activity data is available.

ACTIVITY_FILE="${XDG_CACHE_HOME:-$HOME/.cache}/auto-dim-last-activity"
[[ -z "$ACTIVITY_FILE" ]] && ACTIVITY_FILE="$HOME/.cache/auto-dim-last-activity"

if [[ -f "$ACTIVITY_FILE" ]]; then
    last=$(cat "$ACTIVITY_FILE" 2>/dev/null || echo 0)
    if [[ "$last" =~ ^[0-9]+$ ]]; then
        now=$(date +%s)
        echo $(( now - last ))
        exit 0
    fi
fi

echo 0
