#!/bin/bash
# idle-tracker.sh — background activity tracker for auto-dim.
# Listens to hyprctl monitor events and updates the last-activity
# timestamp that idle-check.sh reads.
#
# Add to Hyprland autostart (e.g. ~/.config/hypr/autostart.lua):
#   exec-once = ~/.config/omarchy/plugins/gerygerger.power/idle-tracker.sh

ACTIVITY_FILE="${XDG_CACHE_HOME:-$HOME/.cache}/auto-dim-last-activity"
[[ -z "$ACTIVITY_FILE" ]] && ACTIVITY_FILE="$HOME/.cache/auto-dim-last-activity"
mkdir -p "$(dirname "$ACTIVITY_FILE")"
touch "$ACTIVITY_FILE"

# Seed the file with "now" so a just-started panel doesn't see
# stale data from before the daemon was running.
date +%s > "$ACTIVITY_FILE"

# hyprctl monitor streams events; any input event counts as activity.
hyprctl monitor 2>/dev/null | while IFS= read -r line; do
    if echo "$line" | grep -qiE 'keydown|keyup|mousemove|mousein|mouseout|scroll|touch|touchdown|touchup'; then
        date +%s > "$ACTIVITY_FILE"
    fi
done
