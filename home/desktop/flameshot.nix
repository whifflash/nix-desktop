{
  config,
  lib,
  pkgs,
  ...
}:
let
  t = config.dynamic.theme.tokens;
in
{
  # Flameshot screenshot tool, run as a tray applet with its capture UI themed
  # from the active palette tokens.
  #
  # Tokens drive the flameshot.ini colours (uiColor = toolbar/handles accent,
  # contrastUiColor = panel behind it, drawColor = default annotation pen). This
  # tracks the *build-time* scheme; it is not swapped live by theme-switcher
  # (flameshot caches its config in the running daemon), so a theme switch shows
  # in flameshot after its next login/daemon restart.
  #
  # Managed declaratively (read-only). home-manager's backupFileExtension moves
  # any pre-existing flameshot.ini to .backup rather than clobbering it.
  config = lib.mkIf config.dynamic.desktop.enable {
    home.packages = [ pkgs.flameshot ];

    xdg.configFile."flameshot/flameshot.ini".text = ''
      [General]
      uiColor=${t.accent1}
      contrastUiColor=${t.bg}
      drawColor=${t.error}
      disabledTrayIcon=false
      showStartupLaunchMessage=false
      showDesktopNotification=true
    '';

    # Tray daemon (StatusNotifierItem → Waybar's tray). XDG_CURRENT_DESKTOP is
    # inherited from whichever compositor imported its environment into the
    # systemd user session (sway or niri), so it is not pinned here.
    systemd.user.services.flameshot = {
      Unit = {
        Description = "Flameshot screenshot tray applet";
        After = [ "graphical-session.target" ];
        PartOf = [ "graphical-session.target" ];
      };
      Service = {
        Type = "simple";
        ExecStart = "${pkgs.flameshot}/bin/flameshot";
        Restart = "on-failure";
        RestartSec = 1;
      };
      Install.WantedBy = [ "graphical-session.target" ];
    };
  };
}
