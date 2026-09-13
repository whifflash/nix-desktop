{ hostConfig, lib, ... }:
let
  t = hostConfig.theme;
  w = hostConfig.waybar;
  f = hostConfig.features;
in
{
  # config.toml → NixOS options: the single translation point for the shared
  # desktop layer on the system side. nixos/ui and nixos/desktop read options
  # only, so they stay identical across consumers. mkDefault throughout, so a
  # host module can still override any value.
  #
  # Deliberately NOT fed from TOML (set them in the consumer's nix):
  #   ui.theme.wallpapersDir         — a nix path into the consumer's repo
  #   ui.theme.swaylock.image        — ditto
  #   desktop.sway.replaceDefaultSession — depends on what else references the
  #                                    stock "sway" session name (e.g. Jovian)
  ui.theme = {
    scheme = lib.mkDefault t.scheme;
    wallpaper = lib.mkDefault (if t.wallpaperEnable then t.wallpaperFile else null);
    wallpaperMode = lib.mkDefault t.wallpaperMode;
    stylix.enable = lib.mkDefault t.stylix;
  };

  ui.waybar = {
    batteryName = lib.mkDefault w.batteryName;
    networkInterface = lib.mkDefault w.networkInterface;
    tempHwmonPath = lib.mkDefault w.tempHwmonPath;
    weatherLocation = lib.mkDefault w.weatherLocation;
  };

  # The WM switches. nixos/desktop/{sway,niri} are always imported and gate on
  # these (both may be on — the login greeter then offers a session chooser).
  programs.sway.enable = lib.mkDefault f.sway;
  programs.niri.enable = lib.mkDefault f.niri;
}
