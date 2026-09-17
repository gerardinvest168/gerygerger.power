#!/bin/bash

# omarchy:summary=Read or set display brightness for the Omarchy bar slider.
# omarchy:args=[monitor] get|set <percent>
# omarchy:examples=brightness.sh get | brightness.sh set 45 | brightness.sh eDP-1 set 45
#
# Resolution order per monitor:
#   1. hardware backlight (internal panel / DDC/CI external) via the omarchy CLI
#   2. software dimming via the managed hyprsunset daemon (hyprctl hyprsunset
#      gamma) for displays with no backlight channel (e.g. external monitors
#      without DDC). Applies to all outputs.

monitor="${1:-}"
action="${2:-get}"
percent="${3:-}"

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

# Clear any software-dim: Hyprland only allows a single CTM manager on the
# compositor and the omarchy hyprsunset service (night light/blue light) owns
# it, so the daemon itself is the dimmer. Lower the gamma to 100, leaving the
# night-light temperature untouched (hyprsunset composes both into one CTM).
soft_clear() {
  hyprctl hyprsunset gamma 100 >/dev/null 2>&1
}

# Current software-dim level, read straight from the daemon. Fall back to 100
# when it is unreachable or reporting identity.
soft_get() {
  local g=""
  g="$(hyprctl hyprsunset gamma 2>/dev/null | grep -oE '[0-9]+(\.[0-9]+)?' | head -n1)"
  [[ $g =~ ^[0-9]+(\.[0-9]+)?$ ]] && (( $(printf '%.0f' "$g") >= 0 && $(printf '%.0f' "$g") <= 100 )) && { printf '%.0f\n' "$g"; return 0; }
  echo 100
}

soft_set() {
  local p="$1"
  if (( p >= 100 )); then
    soft_clear
    echo 100
    return 0
  fi
  hyprctl hyprsunset gamma "$p" >/dev/null 2>&1
  soft_get
}

if [[ $action == "get" ]]; then
  hardware_percent && exit 0
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