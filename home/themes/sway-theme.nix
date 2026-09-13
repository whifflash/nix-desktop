{
  lib,
  config,
  osConfig ? { },
  ...
}:
let
  cfg = config.dynamic.wallpaper;

  # Host-provided defaults via the shared option interface (ui.theme.*), guarded
  # so the module also evaluates without a NixOS host (standalone HM).
  host = lib.attrByPath [ "ui" "theme" ] { } osConfig;
  hostOr = name: fallback: if (host.${name} or null) == null then fallback else host.${name};

  existsIn = dir: file: (dir != null) && (builtins.pathExists "${toString dir}/${file}");
in
{
  options.dynamic.wallpaper = {
    enable = lib.mkEnableOption "desktop wallpaper (Sway background, niri swaybg) + swaylock image";

    dir = lib.mkOption {
      type = lib.types.nullOr lib.types.path;
      default = hostOr "wallpapersDir" null;
      description = "Directory containing wallpapers. Defaults to the host's ui.theme.wallpapersDir.";
    };

    file = lib.mkOption {
      type = lib.types.str;
      default = hostOr "wallpaper" "default.jpg";
      description = "Wallpaper filename inside `dir`. Defaults to the host's ui.theme.wallpaper.";
    };

    mode = lib.mkOption {
      type = lib.types.enum [
        "fill"
        "fit"
        "stretch"
        "tile"
        "center"
      ];
      default = hostOr "wallpaperMode" "fill";
      description = "Background scaling mode. Defaults to the host's ui.theme.wallpaperMode.";
    };

    swaylockImage = lib.mkOption {
      type = lib.types.nullOr lib.types.path;
      default = lib.attrByPath [ "swaylock" "image" ] null host;
      description = ''
        Optional explicit swaylock image (defaults to the host's
        ui.theme.swaylock.image). When null, the wallpaper above is reused.
      '';
    };

    perOutput = lib.mkOption {
      type = lib.types.attrsOf (
        lib.types.submodule (_: {
          options = {
            file = lib.mkOption {
              type = lib.types.str;
              description = "Filename relative to `dir`.";
            };
            mode = lib.mkOption {
              type = lib.types.enum [
                "fill"
                "fit"
                "stretch"
                "tile"
                "center"
              ];
              default = cfg.mode;
            };
          };
        })
      );
      default = { };
      description = "Map of sway output name to its own wallpaper.";
    };

    linkToPictures = lib.mkOption {
      type = lib.types.bool;
      default = true;
      description = "Symlink wallpaper directory to ~/Pictures/wallpapers.";
    };

    resolvedImagePath = lib.mkOption {
      type = lib.types.str;
      readOnly = true;
      description = "Absolute path to the wallpaper image used for swaylock.";
    };
  };

  config = lib.mkIf cfg.enable (
    let
      baseBg = "${toString cfg.dir}/${cfg.file} ${cfg.mode}";

      perOut = lib.mapAttrs (_name: o: {
        bg = "${toString cfg.dir}/${o.file} ${o.mode}";
      }) cfg.perOutput;

      outputs =
        if cfg.perOutput != { } then
          perOut
        else
          {
            "*" = {
              bg = baseBg;
            };
          };

      imagePath =
        if cfg.swaylockImage != null then toString cfg.swaylockImage else "${toString cfg.dir}/${cfg.file}";
    in
    {
      assertions = [
        {
          assertion = cfg.dir != null && builtins.pathExists cfg.dir;
          message = "dynamic.wallpaper: set dynamic.wallpaper.dir (or the host's ui.theme.wallpapersDir) to an existing directory; got ${toString cfg.dir}";
        }
        {
          assertion = (cfg.perOutput != { }) || existsIn cfg.dir cfg.file;
          message = "dynamic.wallpaper: wallpaper '${cfg.file}' not found in ${toString cfg.dir}";
        }
        {
          assertion = lib.all (o: existsIn cfg.dir o.file) (lib.attrValues cfg.perOutput);
          message = "dynamic.wallpaper: one or more perOutput wallpapers were not found in ${toString cfg.dir}";
        }
      ];

      dynamic.wallpaper.resolvedImagePath = imagePath;

      home.file = lib.mkIf cfg.linkToPictures {
        "Pictures/wallpapers".source = cfg.dir;
      };

      wayland.windowManager.sway.config.output = lib.mkForce outputs;
    }
  );
}
