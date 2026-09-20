#!/bin/bash
# idle-tracker.sh — background activity tracker for auto-dim.
# Listens to Hyprland socket2 input events and updates the last-activity
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

# hyprctl has no blocking monitor/event command ("unknown request"), so
# stream input events from Hyprland's socket2 instead. Any keyboard, mouse,
# scroll, or touch event counts as activity.
SOCKET="$XDG_RUNTIME_DIR/hypr/$HYPRLAND_INSTANCE_SIGNATURE/.socket2.sock"

if [[ ! -S "$SOCKET" ]]; then
  echo "idle-tracker: hyprland event socket not found at $SOCKET" >&2
  exit 1
fi

while IFS= read -r line; do
  if [[ $line =~ ^(keyboardkey|mousebutton|mousemov|mousemot|scroll|touch|pinch|swipe|mousezoom) ]]; then
    date +%s > "$ACTIVITY_FILE"
  fi
done < <(socat -U - "UNIX-CONNECT:$SOCKET")
