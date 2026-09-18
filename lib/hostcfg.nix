# Normalise a consumer's config.toml into the `hostConfig` attrset that the
# hostcfg-feed modules read (nixos/hostcfg-feed.nix, home/hostcfg-feed.nix).
#
# Only the sections the SHARED layer understands get defaults here. A consumer
# passes its own sections (and their defaults) via `extraDefaults`, then applies
# any repo-specific validation on the result:
#
#   hostConfig = nix-desktop.lib.mkHostConfig {
#     raw = builtins.fromTOML (builtins.readFile ./hosts/mia/config.toml);
#     extraDefaults = { features.docker = false; vpn = { ... }; };
#   };
#
# Filling defaults means a partial config.toml still evaluates instead of
# throwing "attribute 'X' missing" at a far-off call site, and it lets modules
# drop the `or false` scatter. Lists (e.g. gopass.stores) are replaced, not
# merged, by the consumer's value.
{ lib }:
let
  sharedDefaults = {
    # Which Wayland WMs the host offers at login (both may be on).
    features = {
      sway = false;
      niri = false;
    };

    # → ui.theme.* (nixos/ui/theme.nix). wallpapersDir is a nix PATH and is set
    # by the consumer directly (ui.theme.wallpapersDir = ./resources/wallpapers).
    theme = {
      scheme = "catppuccin-macchiato"; # a palette in home/themes/palettes/
      wallpaperEnable = false;
      wallpaperFile = "default.jpg";
      wallpaperMode = "fill"; # fill | fit | stretch | tile | center
      stylix = false;
    };

    # → dynamic.desktop.* (home/desktop/options.nix). Scalars only; the
    # file-valued knobs (kanshi profiles, niri outputs) are nix paths the
    # consumer sets in its home entry. "" means "not set".
    desktop = {
      keyboardLayout = "us";
      keyboardVariant = "";
      keyboardOptions = "";
      touchpadTap = true;
      scratchpadCommand = ""; # "" = module default (zellij "scratch" session)
      scratchpadKey = "i"; # drop-down toggle is Mod+<this>
      waybarVpnWg = ""; # NetworkManager connection names; "" = no toggle button
      waybarVpnOvpn = "";
      waybarDisplayDocked = ""; # kanshi profile names; "" = no display buttons
      waybarDisplayLaptop = "";
    };

    # → ui.waybar.* (nixos/ui/desktop.nix): machine facts for the bar.
    waybar = {
      batteryName = "BAT0";
      networkInterface = "wlan0";
      weatherLocation = ""; # empty → wttr.in auto-locates by IP
      tempHwmonPath = "/sys/class/hwmon/hwmon0/temp1_input";
    };

    # → dynamic.gopass.* (home/apps/gopass.nix).
    gopass = {
      defaultStore = "~/.password-store";
      stores = [ "~/.password-store" ];
    };

    # → dynamic.zellij.* (home/apps/zellij.nix). [[zellij.tabs]] declares the
    # STABLE tabs of the drop-down session (name + optional cwd/command) so their
    # names cannot go missing on restore. Ad-hoc tabs still return via zellij's
    # own session serialization.
    zellij = {
      tabs = [ ];
      defaultShell = "";
    };

    # → services.repo-sync.instances (home/services/repo-sync.nix). One TOML
    # table per instance: [repoSync.<name>] forge baseUrl destDir environmentFile …
    repoSync = { };
  };

  mkHostConfig =
    {
      raw,
      extraDefaults ? { },
    }:
    lib.recursiveUpdate (lib.recursiveUpdate sharedDefaults extraDefaults) raw;
in
{
  inherit sharedDefaults mkHostConfig;
}
