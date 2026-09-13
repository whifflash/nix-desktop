#!/usr/bin/env bash
# Per-connection VPN indicator + toggle for Waybar.
#
#   status <conn> [label]  -> JSON {text,class,tooltip} for one NM connection.
#                             Empty text if the connection isn't configured
#                             (so a disabled tunnel takes no space).
#   toggle <conn>          -> bring the connection up if it's down (or down if
#                             up), then nudge Waybar to refresh instantly.
#
# Colours come from the theme via CSS classes (.active/.inactive -> @success /
# @muted in style.css). No IP is ever shown - safe to screen-share.
set -uo pipefail

signal=11 # must match "signal": 11 on the custom/vpn-* modules (SIGRTMIN+11)

cmd="${1:-status}"
conn="${2:-}"
label="${3:-$conn}"

all_names() { nmcli -t -f NAME connection show 2>/dev/null || true; }
listed() { printf '%s\n' "$1" | grep -qxF -- "$2"; }

# Print the NetworkManager active-connection STATE for $1 — 'activated' (tunnel
# up) or 'activating' (still connecting, no tunnel yet) — or empty when the
# connection is not active at all (down). We read the STATE column of
# `connection show --active` (the same table you can inspect by hand), which is
# the reliable source: a VPN layered on the wifi shows DEVICE=wlan0, and
# per-connection `-g GENERAL.STATE` can report that base device as 'activated'
# and stay green while the tunnel itself is only 'activating'.
#
# nmcli -t escapes ':' inside a field as '\:'; VPN connection names have none,
# so splitting the "NAME:STATE" line on ':' is safe here.
conn_state() {
  nmcli -t -f NAME,STATE connection show --active 2>/dev/null |
    awk -F: -v c="$1" '$1 == c { print $2; exit }'
}

case "$cmd" in
status)
  if [ -z "$conn" ] || ! listed "$(all_names)" "$conn"; then
    printf '{"text":""}\n'
    exit 0
  fi
  case "$(conn_state "$conn")" in
  activated)
    printf '{"text":"%s","class":"active","tooltip":"%s: up - click to disconnect"}\n' "$label" "$conn"
    ;;
  activating)
    printf '{"text":"%s","class":"activating","tooltip":"%s: connecting - click to cancel"}\n' "$label" "$conn"
    ;;
  *)
    printf '{"text":"%s","class":"inactive","tooltip":"%s: down - click to connect"}\n' "$label" "$conn"
    ;;
  esac
  ;;
toggle)
  [ -n "$conn" ] || exit 1
  # Run detached so a click never blocks Waybar (OpenVPN can take a few seconds).
  (
    # Any active state (activated OR activating) -> bring it down (this also
    # cancels a stuck 'activating'); otherwise bring it up.
    if [ -n "$(conn_state "$conn")" ]; then
      nmcli connection down "$conn"
    else
      nmcli connection up "$conn"
    fi
    pkill -RTMIN+"$signal" waybar
  ) >/dev/null 2>&1 &
  ;;
*)
  echo "usage: vpn-status.sh {status <conn> [label] | toggle <conn>}" >&2
  exit 1
  ;;
esac
