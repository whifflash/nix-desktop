{
  config,
  lib,
  osConfig ? { },
  ...
}:
{
  # Shared Wayland desktop shell. Imported unconditionally by consumers: every
  # piece self-gates on `dynamic.desktop.enable` (on when the host enables Sway
  # or niri) and the WM leaves additionally on `osConfig.programs.<wm>.enable`.
  imports = [
    ./options.nix
    ./wayland-common.nix
    ./waybar.nix
    ./notifications.nix
    ./swaylock.nix
    ./kanshi.nix
    ./flameshot.nix
    ./sway.nix
    ./niri.nix
  ];

  # Wallpaper (Sway `output * bg`, niri swaybg, swaylock image) whenever the host
  # names one via ui.theme.wallpaper. Consumers may override.
  dynamic.wallpaper.enable = lib.mkDefault (
    config.dynamic.desktop.enable && (lib.attrByPath [ "ui" "theme" "wallpaper" ] null osConfig) != null
  );
}
