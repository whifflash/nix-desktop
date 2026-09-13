{
  config,
  lib,
  pkgs,
  ...
}:
{
  # niri — a scrollable-tiling Wayland compositor. Uses nixpkgs' `programs.niri`
  # module (present since nixos-25.05), which installs niri, registers the `niri`
  # wayland session in services.displayManager.sessionPackages, wires the
  # gnome+gtk xdg portals and gnome-keyring, and ships the `niri-session` wrapper
  # that sets up the graphical-session systemd target.
  #
  # The shared Wayland tooling + greetd fallback live in ./wayland-common.nix;
  # this module only adds the niri session command and xwayland-satellite for
  # X11 support (spawned from home/desktop/niri.nix).
  #
  # sway and niri can be enabled together: each registers its own wayland session
  # and the login greeter picks between them, so there is no mutual-exclusion
  # assertion. Applies only when the host sets programs.niri.enable; imported
  # unconditionally so consumers need no import ladders.
  imports = [ ./wayland-common.nix ];

  config = lib.mkIf config.programs.niri.enable {
    desktop.wayland = {
      enable = true;
      sessionCommands = [ "niri-session" ];
      extraPackages = [ pkgs.xwayland-satellite ];
    };

    # nemo is the file manager in the shared home layer (wayland-common), so
    # don't pull in Nautilus for the GNOME file-chooser portal.
    programs.niri.useNautilus = false;
  };
}
