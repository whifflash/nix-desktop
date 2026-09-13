{
  config,
  lib,
  pkgs,
  ...
}:
let
  cfg = config.dynamic.desktop;
in
{
  # Dynamic display configuration for Sway, driven by kanshi.
  #
  # kanshi watches the connected outputs and applies the first matching profile
  # from ~/.config/kanshi/config — installed verbatim from
  # dynamic.desktop.kanshi.config (a consumer-supplied file keyed on stable
  # manufacturer/model/serial aliases rather than volatile DP-N connector names).
  # Off entirely when that option is null.
  #
  # Two optional Waybar buttons (dynamic.desktop.waybar.displayProfiles) let you
  # *force* a profile regardless of what auto-matching would pick; both call
  # dotfiles/waybar/scripts/display-profile.sh, which runs `kanshictl switch
  # <profile>` and records the choice so the live layout's button highlights.
  #
  # Hand-rolled as a systemd user service (rather than home-manager's
  # services.kanshi) to keep the exact config file above and to match the
  # nm-applet / polkit-gnome services in ./wayland-common.nix.
  config = lib.mkIf (cfg.enable && cfg.kanshi.config != null) {
    home.packages = [ pkgs.kanshi ]; # provides both `kanshi` and `kanshictl`

    home.file = {
      ".config/kanshi/config".source = cfg.kanshi.config;

      ".config/waybar/scripts/display-profile.sh" = {
        source = ./dotfiles/waybar/scripts/display-profile.sh;
        executable = true;
      };
    };

    systemd.user.services.kanshi = {
      Unit = {
        Description = "kanshi dynamic display configuration daemon";
        Documentation = [ "man:kanshi(1)" ];
        After = [ "graphical-session.target" ];
        PartOf = [ "graphical-session.target" ];
      };
      Service = {
        Type = "simple";
        ExecStart = "${pkgs.kanshi}/bin/kanshi";
        ExecReload = "${pkgs.kanshi}/bin/kanshictl reload";
        Restart = "on-failure";
        RestartSec = 1;
      };
      Install.WantedBy = [ "graphical-session.target" ];
    };
  };
}
