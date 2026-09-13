#!/usr/bin/env bash
#
# Waybar <-> kanshi bridge for the two display-profile buttons in the top-left.
#
#   display-profile.sh switch <profile> [<role>]   apply a kanshi profile, then refresh
#                                                  both buttons so the live one lights up
#   display-profile.sh status <profile> [<role>]   emit Waybar JSON (active/inactive +
#                                                  tooltip) for one profile
#
# <profile> is the kanshi profile name (consumer-specific, fed from
# dynamic.desktop.waybar.displayProfiles); <role> is which button this is
# (docked | laptop) and only picks the human-readable tooltip.
#
# kanshi normally auto-selects a profile from the connected outputs; `kanshictl
# switch` forces one regardless (e.g. drop to laptop-only while still docked).
# The chosen profile is remembered in a small state file so the matching button
# can be highlighted via its `.active` CSS class.
set -euo pipefail

state="${XDG_RUNTIME_DIR:-/tmp}/kanshi-active-profile"

# Real-time signal Waybar listens on to re-run the two indicator modules.
# Must match "signal": 9 on custom/display-* in modules.json (SIGRTMIN+9).
signal=9

label_for() {
  local profile="$1" role="${2:-}"
  case "$role" in
  docked) printf 'Docked \xe2\x80\x94 %s' "$profile" ;;
  laptop) printf 'Laptop only \xe2\x80\x94 %s' "$profile" ;;
  *) printf '%s' "$profile" ;;
  esac
}

case "${1:-status}" in
switch)
  profile="${2:?usage: display-profile.sh switch <profile> [<role>]}"
  kanshictl switch "$profile"
  printf '%s' "$profile" >"$state"
  # Nudge Waybar so both buttons immediately re-read the state file.
  pkill -RTMIN+"$signal" waybar 2>/dev/null || true
  ;;
status)
  profile="${2:?usage: display-profile.sh status <profile> [<role>]}"
  active=""
  [ -r "$state" ] && active="$(cat "$state")"
  label="$(label_for "$profile" "${3:-}")"
  if [ "$profile" = "$active" ]; then
    printf '{"class":"active","tooltip":"%s (active)"}\n' "$label"
  else
    printf '{"class":"inactive","tooltip":"Switch to: %s"}\n' "$label"
  fi
  ;;
*)
  echo "usage: display-profile.sh {switch|status} <profile> [<role>]" >&2
  exit 1
  ;;
esac
