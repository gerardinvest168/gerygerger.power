#!/bin/bash

# omarchy:summary=Read or set display brightness for the Omarchy bar slider.
# omarchy:args=[monitor] get|set <percent>
# omarchy:examples=brightness.sh get | brightness.sh set 45 | brightness.sh eDP-1 set 45
#
# Resolution order per monitor:
#   1. hardware backlight (internal panel / DDC/CI external) via the omarchy CLI
#   2. software dimming via hyprsunset CTM for displays with no backlight
#      channel (e.g. external monitors without DDC). Applies to all outputs.

monitor="${1:-}"
action="${2:-get}"
percent="${3:-}"

STATE_DIR="${XDG_RUNTIME_DIR:-/tmp}/omarchy-brightness-slider"
SOFT_FILE="$STATE_DIR/soft"
PID_FILE="$STATE_DIR/dim.pid"

[[ -n $monitor ]] || monitor="$(omarchy-hyprland-monitor-focused 2>/dev/null || true)"

monitor_is_internal() {
  [[ $monitor =~ ^(eDP|LVDS|DSI)- ]]
}

# Prints the hardware brightness percent and exits 0, or fails if the focused
# display has no controllable backlight channel. For internal panels the raw
# backlight device (brightnessctl) is the fallback; for external monitors only
# DDC/CI counts — a laptop backlight drives eDP-*, which on a lid-closed setup
# is a dark panel, not the external monitor in front of you.
hardware_percent() {
  local out dev
  out="$(omarchy-brightness-display --no-osd --monitor "$monitor" 2>/dev/null)" && [[ -n "$out" ]] && { echo "$out"; return 0; }
  monitor_is_internal || return 1
  dev="$(omarchy-hw-display 2>/dev/null)" || return 1
  [[ -n $dev ]] || return 1
  brightnessctl -d "$dev" -m 2>/dev/null | awk -F, '{ gsub("%", "", $4); print $4; found=1 } END{ exit !found }'
}

# Kill any running software-dim daemon and clear its state, so the display
# matches whatever the hardware path reports (avoids a leftover hyprsunset
# keeping the screen dimmed after a hardware set or a compositor restart
# stale-pid fork).
soft_clear() {
  local old="" pid=""
  if [[ -r $PID_FILE ]]; then
    old="$(cat "$PID_FILE" 2>/dev/null || true)"
    rm -f "$PID_FILE"
    if [[ $old =~ ^[0-9]+$ ]] && kill -0 "$old" >/dev/null 2>&1; then
      kill "$old" >/dev/null 2>&1
    fi
  fi
  rm -f "$SOFT_FILE"
}

# Current software-dim level. If the dimmer daemon died (compositor restart),
# the screen is back at 100% regardless of the stored value.
soft_get() {
  local stored="" pid=""
  if [[ -r $SOFT_FILE ]]; then
    stored="$(cat "$SOFT_FILE" 2>/dev/null || true)"
  fi
  if [[ -r $PID_FILE ]]; then
    pid="$(cat "$PID_FILE" 2>/dev/null || true)"
  fi
  if [[ $pid =~ ^[0-9]+$ ]] && kill -0 "$pid" >/dev/null 2>&1; then
    [[ $stored =~ ^[0-9]+$ ]] && { echo "$stored"; return 0; }
  fi
  echo 100
}

soft_set() {
  local p="$1" old="" pid=""

  mkdir -p "$STATE_DIR" 2>/dev/null || true

  if [[ -r $PID_FILE ]]; then
    old="$(cat "$PID_FILE" 2>/dev/null || true)"
    rm -f "$PID_FILE"
    if [[ $old =~ ^[0-9]+$ ]] && kill -0 "$old" >/dev/null 2>&1; then
      kill "$old" >/dev/null 2>&1
    fi
  fi

  printf '%s\n' "$p" > "$SOFT_FILE"

  if (( p >= 100 )); then
    # Full brightness: release the manager entirely (resets CTM to identity).
    echo "$p"
    return 0
  fi

  # Detach so the daemon outlives this script (Quickshell reaps the direct
  # child). setsid gives it its own session, immune to group-wide kills.
  setsid hyprsunset -g "$p" >/dev/null 2>&1 < /dev/null &
  pid=$!
  printf '%s\n' "$pid" > "$PID_FILE"
  disown "$pid" 2>/dev/null || true

  echo "$p"
}

if [[ $action == "get" ]]; then
  hardware_percent && soft_clear && exit 0
  soft_get
  exit 0
fi

if [[ $action == "set" ]]; then
  [[ $percent =~ ^[0-9]+$ ]] || exit 1
  (( percent > 100 )) && percent=100
  (( percent < 15 )) && percent=15

  if hardware_percent >/dev/null 2>&1; then
    # Hardware path is authoritative: stage the change through the omarchy CLI.
    if ! omarchy-brightness-display --no-osd --monitor "$monitor" "${percent}%" >/dev/null 2>&1; then
      monitor_is_internal || exit 1
      dev="$(omarchy-hw-display 2>/dev/null)" || exit 1
      [[ -n $dev ]] || exit 1
      brightnessctl -d "$dev" set "${percent}%" >/dev/null || exit 1
    fi
    soft_clear
    hardware_percent || echo "$percent"
    exit 0
  fi

  soft_set "$percent"
  exit 0
fi

exit 1