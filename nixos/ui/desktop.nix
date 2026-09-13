{ lib, ... }:
let
  inherit (lib) mkOption types;
in
{
  # Machine facts the Waybar config needs. home/desktop/waybar.nix reads them via
  # `osConfig.ui.waybar` and templates them into modules.json, so they live at
  # the host level (fed from config.toml [waybar] by nixosModules.hostcfg-feed).
  options.ui.waybar = {
    batteryName = mkOption {
      type = types.str;
      default = "BAT0";
      description = "Battery device name (see: ls /sys/class/power_supply).";
    };
    networkInterface = mkOption {
      type = types.str;
      default = "wlan0";
      description = "Wi-Fi interface shown in the bar (pinned so VPN tunnels never show there).";
    };
    tempHwmonPath = mkOption {
      type = types.str;
      default = "/sys/class/hwmon/hwmon0/temp1_input";
      description = "CPU temperature sensor (hwmon path).";
    };
    weatherLocation = mkOption {
      type = types.str;
      default = "";
      description = "wttr.in location; empty auto-locates by IP.";
    };
  };
}
