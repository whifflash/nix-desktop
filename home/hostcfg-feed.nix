{ hostConfig, lib, ... }:
let
  d = hostConfig.desktop;
  nullIfEmpty = s: if s == "" then null else s;
in
{
  # config.toml → home options: the single translation point for the shared
  # desktop layer on the home side. home/themes, home/desktop, home/apps and
  # home/services read dynamic.* / osConfig.ui.* / services.repo-sync only, so
  # they stay identical across consumers. mkDefault throughout, so a consumer's
  # home entry can still override any value.
  #
  # File-valued knobs (dynamic.desktop.kanshi.config, dynamic.desktop.niri.outputs)
  # are nix paths and are set by the consumer directly.
  #
  # Nested under one `dynamic` attrset rather than repeating `dynamic.<x> =`
  # per section — statix flags the repeated key otherwise.
  dynamic = {
    gopass = {
      stores = lib.mkDefault hostConfig.gopass.stores;
      defaultStore = lib.mkDefault hostConfig.gopass.defaultStore;
    };

    # [zellij] → the declared tabs of the drop-down session (home/apps/zellij.nix).
    zellij = {
      tabs = lib.mkDefault hostConfig.zellij.tabs;
      defaultShell = lib.mkDefault hostConfig.zellij.defaultShell;
    };

    desktop = {
      keyboard = {
        layout = lib.mkDefault d.keyboardLayout;
        variant = lib.mkDefault d.keyboardVariant;
        options = lib.mkDefault d.keyboardOptions;
      };
      touchpad.tap = lib.mkDefault d.touchpadTap;
      waybar = {
        vpn = {
          wg = lib.mkDefault (nullIfEmpty d.waybarVpnWg);
          ovpn = lib.mkDefault (nullIfEmpty d.waybarVpnOvpn);
        };
        displayProfiles = {
          docked = lib.mkDefault (nullIfEmpty d.waybarDisplayDocked);
          laptop = lib.mkDefault (nullIfEmpty d.waybarDisplayLaptop);
        };
      };
    }
    // lib.optionalAttrs (d.scratchpadCommand != "") {
      scratchpad.command = lib.mkDefault d.scratchpadCommand;
    };
  };

  # [repoSync.<name>] tables map 1:1 onto services.repo-sync.instances.<name>.
  services.repo-sync.instances = lib.mapAttrs (_: inst: lib.mapAttrs (_: lib.mkDefault) inst) (
    hostConfig.repoSync or { }
  );
}
