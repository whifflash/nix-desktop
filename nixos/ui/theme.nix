{ lib, ... }:
let
  inherit (lib) mkEnableOption mkOption types;
in
{
  # Theme interface between the host and the shared desktop layer. home-manager
  # reads it via `osConfig.ui.theme` (home/themes/tokens.nix, sway-theme.nix,
  # hm-stylix-bridge.nix); modules/ui/stylix-bridge.nix reads it for the system
  # Stylix. Static defaults here — consumers feed real values (via
  # nixosModules.hostcfg-feed from config.toml, or per-host nix).
  options.ui.theme = {
    scheme = mkOption {
      type = types.str;
      default = "catppuccin-macchiato";
      description = "Logical theme name (must match a palette in home/themes/palettes/).";
    };

    wallpapersDir = mkOption {
      type = types.nullOr types.path;
      default = null;
      description = "Directory containing wallpapers (null = no wallpaper).";
    };

    wallpaper = mkOption {
      type = types.nullOr types.str;
      default = null;
      description = "Wallpaper filename relative to wallpapersDir (null = no wallpaper).";
    };

    wallpaperMode = mkOption {
      type = types.enum [
        "fill"
        "fit"
        "stretch"
        "tile"
        "center"
      ];
      default = "fill";
      description = "Background scaling mode (Sway `output bg`, niri swaybg).";
    };

    swaylock.image = mkOption {
      type = types.nullOr types.path;
      default = null;
      description = "Optional explicit swaylock background image (defaults to the wallpaper).";
    };

    stylix.enable = mkOption {
      type = types.bool;
      default = false;
      description = "Enable system + home Stylix integration (image + base16 scheme from the palette).";
    };

    qt.enable = mkEnableOption "Qt theming";
  };
}
