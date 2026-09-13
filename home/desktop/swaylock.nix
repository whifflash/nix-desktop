{
  lib,
  config,
  pkgs,
  ...
}:
let
  wp = config.dynamic.wallpaper;
  T = config.dynamic.theme.tokens;

  strip = s: lib.removePrefix "#" s;

  swaylockConfig = ''
    image=${wp.resolvedImagePath}

    effect-blur=3x5
    scaling=fill
    ignore-empty-password

    indicator
    indicator-radius=120
    indicator-thickness=20
    indicator-caps-lock
    clock
    timestr=%I:%M %p
    datestr=%B, %d

    text-color=${strip T.fg}
    font=RobotoMono Nerd Font
    font-size=28

    layout-bg-color=${strip T.bgAlt}
    layout-border-color=${strip T.borderMuted}
    layout-text-color=${strip T.fg}

    ring-color=${strip T.bg}DD
    line-color=${strip T.bg}99
    inside-color=${strip T.bg}11

    separator-color=${strip T.bg}99

    ring-ver-color=${strip T.success}DD
    line-ver-color=${strip T.success}99
    inside-ver-color=${strip T.bg}11
    text-ver-color=${strip T.fg}

    ring-clear-color=${strip T.success}DD
    line-clear-color=${strip T.success}99
    inside-clear-color=${strip T.bg}11
    text-clear-color=${strip T.fg}

    ring-wrong-color=${strip T.error}DD
    line-wrong-color=${strip T.error}33
    inside-wrong-color=${strip T.bg}11
    text-wrong-color=${strip T.fg}

    ring-caps-lock-color=${strip T.bg}DD
    line-caps-lock-color=${strip T.bg}99
    inside-caps-lock-color=${strip T.bg}11
    text-caps-lock-color=${strip T.fg}

    key-hl-color=${strip T.fg}
    bs-hl-color=${strip T.warning}
    caps-lock-key-hl-color=${strip T.error}
    caps-lock-bs-hl-color=${strip T.warning}
  '';
in
{
  config = lib.mkIf (config.dynamic.desktop.enable && wp.enable) {
    home.packages = with pkgs; [ swaylock-effects ];
    xdg.configFile."swaylock/config".text = swaylockConfig;
  };
}
