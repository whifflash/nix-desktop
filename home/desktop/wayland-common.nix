{
  config,
  lib,
  pkgs,
  ...
}:
let
  cfg = config.wayland.common;

  # Minimal graphical-session user service bound to graphical-session.target so
  # it starts with the compositor and stops with it. Used for the tray + polkit
  # agent here; flameshot.nix / kanshi.nix could adopt it too.
  mkGraphicalService =
    {
      description,
      exec,
      environment ? [ ],
      restartSec ? null,
    }:
    {
      Unit = {
        Description = description;
        After = [ "graphical-session.target" ];
        PartOf = [ "graphical-session.target" ];
      };
      Service = {
        ExecStart = exec;
        Restart = "on-failure";
      }
      // lib.optionalAttrs (restartSec != null) { RestartSec = restartSec; }
      // lib.optionalAttrs (environment != [ ]) { Environment = environment; };
      Install.WantedBy = [ "graphical-session.target" ];
    };
in
{
  # Shared home-manager base for the Wayland sessions (Sway, niri): the polkit
  # agent, the NetworkManager tray, gnome-keyring, and the apps both sessions
  # use. Each WM's home module enables this and passes its XDG desktop name.
  options.wayland.common = {
    enable = lib.mkEnableOption "shared Wayland home base (tray, polkit agent, keyring, common apps)";
  };

  config = lib.mkIf cfg.enable {
    home.packages = with pkgs; [
      alacritty
      nemo
      networkmanagerapplet
    ];

    services.gnome-keyring.enable = true;

    # Polkit agent for auth prompts (Wi-Fi passwords, VPN, etc.).
    systemd.user.services."polkit-gnome-authentication-agent-1" = mkGraphicalService {
      description = "polkit-gnome authentication agent";
      exec = "${pkgs.polkit_gnome}/libexec/polkit-gnome-authentication-agent-1";
    };

    # NetworkManager applet exposed as a StatusNotifier item for Waybar's tray.
    # XDG_CURRENT_DESKTOP is inherited from whichever compositor imported its
    # environment into the systemd user session (sway or niri), so it is not
    # pinned here — that lets this single service work under either WM.
    systemd.user.services."nm-applet" = mkGraphicalService {
      description = "NetworkManager Applet (tray)";
      exec = "${pkgs.networkmanagerapplet}/bin/nm-applet --indicator";
      restartSec = 1;
    };
  };
}
