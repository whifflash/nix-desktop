{
  lib,
  config,
  options,
  ...
}:
let
  cfg = config.ui.theme;

  # Palette discovery/loading + base16 mapping are shared (see
  # home/themes/palette-lib.nix); scheme/author are this module's own.
  palettes = import ../../home/themes/palette-lib.nix { inherit lib; };
  palette = palettes.loadPalette cfg.scheme;
  base16 = palettes.toBase16 palette.tokens // {
    scheme = palette.name or cfg.scheme;
    author = "generated";
  };

  # The consumer decides whether Stylix is part of its system at all. The
  # `stylix.*` definitions below must not even EXIST when the option is
  # undeclared (the module system rejects definitions for unknown options
  # regardless of any mkIf), hence optionalAttrs rather than mkIf here.
  hasStylix = options ? stylix;
  hasWallpaper = cfg.wallpapersDir != null && cfg.wallpaper != null;
  wallpaperPath = if hasWallpaper then "${cfg.wallpapersDir}/${cfg.wallpaper}" else null;
in
{
  config = lib.mkIf cfg.stylix.enable (
    {
      assertions = [
        {
          assertion = hasStylix;
          message = "ui.theme.stylix.enable requires the Stylix NixOS module (inputs.stylix.nixosModules.stylix) to be imported by the consumer.";
        }
        {
          assertion = hasWallpaper;
          message = "ui.theme.stylix.enable requires ui.theme.wallpapersDir and ui.theme.wallpaper to be set.";
        }
      ];
    }
    // lib.optionalAttrs hasStylix {
      stylix = {
        enable = true;
        base16Scheme = base16;
        image = wallpaperPath;
      };
    }
  );
}
