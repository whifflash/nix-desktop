{
  config,
  lib,
  pkgs,
  ...
}:
let
  cfg = config.desktop.sway;

  # Wayland greeters (SDDM, etc.) only list sessions from
  # services.displayManager.sessionPackages, and NixOS drops the registration
  # unless the package both declares `passthru.providedSessions` and ships a
  # matching share/wayland-sessions/*.desktop whose basename equals the
  # providedSessions entry. Wrap that contract here so new custom sessions are
  # one call away.
  mkWaylandSession =
    {
      name,
      displayName,
      comment ? "",
      script,
    }:
    let
      bin = pkgs.writeShellScriptBin name script;
    in
    pkgs.symlinkJoin {
      name = "${name}-session";
      passthru.providedSessions = [ name ];
      paths = [
        bin
        (pkgs.writeTextFile {
          name = "${name}-desktop";
          destination = "/share/wayland-sessions/${name}.desktop";
          text = ''
            [Desktop Entry]
            Name=${displayName}
            Comment=${comment}
            Exec=${bin}/bin/${name}
            Type=Application
          '';
        })
      ];
    };

  swayDebugSession = mkWaylandSession {
    name = "sway-debug";
    displayName = "Sway (Debug)";
    comment = "Sway with debug logging written to ~/sway_log.log";
    script = ''
      log="$HOME/sway_log.log"
      {
        echo "=== sway-debug started at $(date -Iseconds) ==="
        echo "=== Environment ==="
        env | sort
        echo "=== Starting sway -d ==="
      } > "$log" 2>&1
      exec sway -d >> "$log" 2>&1
    '';
  };
  swayRegularSession = mkWaylandSession {
    name = "sway-regular";
    displayName = "Sway";
    comment = "Sway without debug logging";
    script = ''
      exec sway
    '';
  };

  wrappedSessions = [
    swayDebugSession
    swayRegularSession
  ];
in
{
  imports = [ ./wayland-common.nix ];

  options.desktop.sway.replaceDefaultSession = lib.mkOption {
    type = lib.types.bool;
    default = false;
    description = ''
      When true, REPLACE pkgs.sway's stock login session with the wrapped
      `sway-regular` / `sway-debug` sessions only. The stock sway.desktop sets
      DesktopNames=sway;wlroots, which makes some greeters export
      XDG_CURRENT_DESKTOP=sway:wlroots into the launched session — that can tear
      the wayland display down after a few seconds. Leave false wherever
      something references the stock session by its name "sway" (e.g. Jovian's
      `desktopSession = "sway"`); the wrapped sessions are then offered in
      addition to it.
    '';
  };

  # Applies only when the host enables Sway (programs.sway.enable); imported
  # unconditionally so consumers need no import ladders.
  config = lib.mkIf config.programs.sway.enable {
    # Shared Wayland base (tooling, keyring, greetd fallback) plus Sway's own
    # session command and the wlroots software-cursor workaround.
    desktop.wayland = {
      enable = true;
      sessionCommands = [ "sway" ];
      extraSessionVariables.WLR_NO_HARDWARE_CURSORS = "1";
    };

    programs.sway.wrapperFeatures.gtk = true;

    # Register the wrapped sessions. With replaceDefaultSession, mkForce replaces
    # the whole list (dropping pkgs.sway's auto-appended default), so niri's
    # session package is re-added here when niri is on — otherwise mkForce would
    # drop the one programs.niri registered and only Sway would show up in the
    # login chooser. pkgs.niri ships passthru.providedSessions = ["niri"].
    services.displayManager.sessionPackages =
      if cfg.replaceDefaultSession then
        lib.mkForce (wrappedSessions ++ lib.optional config.programs.niri.enable pkgs.niri)
      else
        wrappedSessions;
  };
}
