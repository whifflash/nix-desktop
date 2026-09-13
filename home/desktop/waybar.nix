{
  config,
  lib,
  pkgs,
  osConfig ? { },
  ...
}:
let
  cfg = config.dynamic.desktop;

  # Machine facts (battery / Wi-Fi iface / thermal sensor / weather location)
  # come from the host's ui.waybar (nixos/ui/desktop.nix); fall back to sane
  # defaults so the module also evaluates without a host feed.
  wb = {
    batteryName = "BAT0";
    networkInterface = "wlan0";
    tempHwmonPath = "/sys/class/hwmon/hwmon0/temp1_input";
    weatherLocation = "";
  }
  // lib.attrByPath [ "ui" "waybar" ] { } osConfig;

  # Streaming Waybar module: number of windows on the focused workspace. Branches
  # on the WM socket (niri via `niri msg`, Sway via `swaymsg`), excludes the
  # drop-down scratch terminal, and updates off each WM's event stream (no
  # polling) — printing only when the count actually changes.
  windowCount = pkgs.writeShellScript "waybar-window-count" ''
    set -uo pipefail
    last=""
    # Emits "<focused position>/<total>" (e.g. 3/7) for the current workspace, in
    # visual order — niri by (column, tile), Sway by tree order. Falls back to
    # just the total if the focused window isn't one of them (e.g. the dropdown),
    # and "0" for an empty workspace. The drop-down scratch terminal is excluded.
    emit() {
      local n="" ws="" fw=""
      if [ -n "''${NIRI_SOCKET:-}" ]; then
        ws=$(niri msg -j workspaces | ${pkgs.jq}/bin/jq -r 'map(select(.is_focused)) | .[0].id // empty') || return 0
        [ -n "$ws" ] || return 0
        n=$(niri msg -j windows | ${pkgs.jq}/bin/jq -r --argjson ws "$ws" --arg dd "${cfg.scratchpad.appId}" '[ .[] | select(.workspace_id == $ws and (.app_id // "") != $dd and .layout.pos_in_scrolling_layout != null) ] | sort_by(.layout.pos_in_scrolling_layout) | (map(.is_focused) | index(true)) as $i | length as $t | if $t == 0 then "0" elif $i == null then "\($t)" else "\($i + 1)/\($t)" end') || return 0
      elif [ -n "''${SWAYSOCK:-}" ]; then
        fw=$(swaymsg -t get_workspaces | ${pkgs.jq}/bin/jq -r '.[] | select(.focused) | .name') || return 0
        [ -n "$fw" ] || return 0
        n=$(swaymsg -t get_tree | ${pkgs.jq}/bin/jq -r --arg ws "$fw" --arg dd "${cfg.scratchpad.title}" '[ .. | objects | select(.type? == "workspace" and .name? == $ws) | recurse(.nodes[]?, .floating_nodes[]?) | select(.pid? != null and .name? != $dd) ] | (map(.focused) | index(true)) as $i | length as $t | if $t == 0 then "0" elif $i == null then "\($t)" else "\($i + 1)/\($t)" end') || return 0
      else
        return 0
      fi
      [ -n "$n" ] || return 0
      [ "$n" = "$last" ] && return 0
      last="$n"
      printf '{"text":"%s","tooltip":"focused window / windows on this workspace"}\n' "$n"
    }

    emit
    if [ -n "''${NIRI_SOCKET:-}" ]; then
      niri msg event-stream | while IFS= read -r line; do
        case "$line" in *Window*|*Workspace*) emit ;; esac
      done
    elif [ -n "''${SWAYSOCK:-}" ]; then
      swaymsg -t subscribe '["window","workspace"]' | while IFS= read -r _; do emit; done
    else
      exec sleep infinity
    fi
  '';

  # Optional module groups. The dotfiles carry @WB_*@ placeholders; a group is
  # spliced into the bar's module list only when its feed is set (null omits it),
  # so a host without VPN tunnels or kanshi profiles gets a clean bar.
  vpnModules = lib.concatStringsSep " " (
    lib.optional (cfg.waybar.vpn.wg != null) ''"custom/vpn-wg",''
    ++ lib.optional (cfg.waybar.vpn.ovpn != null) ''"custom/vpn-ovpn",''
  );
  displayModules = lib.optionalString (
    cfg.kanshi.config != null && cfg.waybar.displayProfiles.docked != null
  ) ''"custom/display-docked", "custom/display-laptop",'';
  orEmpty = v: if v == null then "" else v;

  template =
    file:
    builtins.replaceStrings
      [
        "@WB_BATTERY@"
        "@WB_IFACE@"
        "@WB_HWMON@"
        "@WB_WEATHER@"
        "@WB_WINCOUNT@"
        "@WB_VPN_WG@"
        "@WB_VPN_OVPN@"
        "@WB_DISPLAY_DOCKED@"
        "@WB_DISPLAY_LAPTOP@"
        "@WB_VPN_MODULES@"
        "@WB_DISPLAY_MODULES@"
      ]
      [
        wb.batteryName
        wb.networkInterface
        wb.tempHwmonPath
        wb.weatherLocation
        "${windowCount}"
        (orEmpty cfg.waybar.vpn.wg)
        (orEmpty cfg.waybar.vpn.ovpn)
        (orEmpty cfg.waybar.displayProfiles.docked)
        (orEmpty cfg.waybar.displayProfiles.laptop)
        vpnModules
        displayModules
      ]
      (builtins.readFile file);
in
{
  config = lib.mkIf cfg.enable {
    home.packages = with pkgs; [
      waybar
      gsimplecal
    ];

    home.file = {
      ".config/waybar/config".text = template ./dotfiles/waybar/config;
      ".config/waybar/modules.json".text = template ./dotfiles/waybar/modules.json;
      ".config/waybar/ornamental.json".source = ./dotfiles/waybar/ornamental.json;
      ".config/waybar/ornamental.css".source = ./dotfiles/waybar/ornamental.css;
      ".config/waybar/style.css".source = ./dotfiles/waybar/style.css;
      ".config/gsimplecal/config".source = ./dotfiles/gsimplecal/config;
      ".config/waybar/launch_waybar.sh" = {
        source = ./dotfiles/waybar/launch_waybar.sh;
        executable = true;
      };
      # Modular "restart Waybar cleanly", used by niri's Mod+Shift+R. `pkill waybar`
      # (substring) is deliberate and mirrors launch_waybar.sh: wrapGAppsHook renames
      # the real binary to `.waybar-wrapped`, so `pkill -x waybar` never matches the
      # running process and instances stack up. A script's own comm is "bash", so
      # this never kills itself.
      ".config/waybar/reload_waybar.sh" = {
        text = ''
          #!/usr/bin/env bash
          pkill waybar
          sleep 0.2
          exec ${pkgs.waybar}/bin/waybar
        '';
        executable = true;
      };
      # Generic: takes the NM connection name as an argument (from modules.json).
      ".config/waybar/scripts/vpn-status.sh" = {
        source = ./dotfiles/waybar/scripts/vpn-status.sh;
        executable = true;
      };
    };
  };
}
