{
  config,
  lib,
  pkgs,
  ...
}:
let
  cfg = config.desktop.wayland;
in
{
  # Shared base for the Wayland desktop modules (Sway, niri): the common tool
  # set, gnome-keyring, polkit, NIXOS_OZONE_WL, and the tuigreet/greetd fallback
  # session. Each WM module enables this and passes its own session command +
  # extras. Reads only NixOS options (no repo-specific config source), so it is
  # shareable across consumers.
  options.desktop.wayland = {
    enable = lib.mkEnableOption "shared Wayland desktop base (tooling, keyring, greetd fallback)";

    sessionCommands = lib.mkOption {
      type = lib.types.listOf lib.types.str;
      default = [ ];
      example = [ "sway" ];
      description = ''
        Session commands contributed by the enabled Wayland WMs. With exactly one,
        tuigreet launches it directly (--cmd); with more than one, tuigreet shows a
        session chooser populated from the registered wayland-sessions. SDDM, when
        enabled, ignores this and lists the sessions itself.
      '';
    };

    extraPackages = lib.mkOption {
      type = lib.types.listOf lib.types.package;
      default = [ ];
      description = "Packages appended to the shared Wayland tool set.";
    };

    extraSessionVariables = lib.mkOption {
      type = lib.types.attrsOf lib.types.str;
      default = { };
      description = "Extra environment.sessionVariables merged into the Wayland base.";
    };
  };

  config = lib.mkIf cfg.enable {
    environment.sessionVariables = {
      NIXOS_OZONE_WL = "1";
    }
    // cfg.extraSessionVariables;

    services.gnome.gnome-keyring.enable = true;
    # Auth prompts (Wi-Fi/VPN passwords via the polkit-gnome agent in home).
    # Harmless if a consumer also enables it globally.
    security.polkit.enable = true;

    environment.systemPackages =
      (with pkgs; [
        grim
        slurp
        wl-clipboard
        waybar
        wofi
        swaylock-effects
        libnotify
        pavucontrol
        networkmanagerapplet
        wdisplays
      ])
      ++ cfg.extraPackages
      ++ [ pkgs.tuigreet ];

    # Provide a greeter unless SDDM is supplying one. With a single WM tuigreet
    # launches it directly; with several it shows a session chooser drawn from the
    # same wayland-sessions SDDM would list.
    services.greetd = lib.mkIf (!config.services.displayManager.sddm.enable) {
      enable = true;
      settings.default_session = {
        user = "greeter";
        command =
          let
            base = "${pkgs.tuigreet}/bin/tuigreet --time --time-format '%I:%M %p | %a • %h | %F'";
          in
          if lib.length cfg.sessionCommands == 1 then
            "${base} --cmd ${lib.head cfg.sessionCommands}"
          else
            "${base} --remember --remember-session --sessions ${config.services.displayManager.sessionData.desktops}/share/wayland-sessions";
      };
    };
  };
}
