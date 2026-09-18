# Evaluation smoke test: instantiate a stub NixOS system that imports every
# module of this flake with representative TOML knobs, both WMs on, wallpaper,
# gopass stores, a kanshi profile, niri outputs and two repo-sync instances.
# Only `drvPath` is forced — nothing is built — so this catches option, type and
# module-plumbing errors against the given nixpkgs/home-manager pair in ~1 min.
# The context is discarded so the check does not depend on building the system.
{
  self,
  nixpkgs,
  home-manager,
  system ? "x86_64-linux",
}:
let
  inherit (nixpkgs) lib;
  pkgs = import nixpkgs { inherit system; };

  hostConfig = self.lib.mkHostConfig {
    raw = {
      features = {
        sway = true;
        niri = true;
      };
      theme = {
        scheme = "nord";
        wallpaperEnable = true;
        wallpaperFile = "wallpaper.png";
      };
      desktop = {
        keyboardLayout = "eu";
        keyboardOptions = "caps:super";
        touchpadTap = false;
        waybarVpnWg = "vpn-wg";
        waybarVpnOvpn = "vpn-ovpn";
        waybarDisplayDocked = "docked";
        waybarDisplayLaptop = "laptop";
      };
      gopass = {
        defaultStore = ".password-store-a";
        stores = [
          ".password-store-a"
          "~/.password-store-b"
        ];
      };
      repoSync = {
        forge-a = {
          forge = "gitea";
          baseUrl = "https://git.example.com";
          environmentFile = "/run/secrets/gitea.env";
          sshPort = 2222;
        };
        forge-b = {
          forge = "gitlab";
          baseUrl = "https://gitlab.example.com";
          environmentFile = "/run/secrets/gitlab.env";
          intervalSec = 7200;
          randomizedDelaySec = 0;
        };
      };
    };
  };

  sys = lib.nixosSystem {
    inherit system;
    specialArgs = { inherit hostConfig; };
    modules = [
      home-manager.nixosModules.home-manager
      self.nixosModules.default
      self.nixosModules.hostcfg-feed
      {
        # Minimal bootable-looking stub so NixOS's own assertions pass.
        boot.loader.grub.enable = false;
        fileSystems."/" = {
          device = "none";
          fsType = "tmpfs";
        };
        system.stateVersion = "26.05";
        users.users.smoke.isNormalUser = true;

        # Consumer-side (non-TOML) settings.
        ui.theme.wallpapersDir = ./assets;
        desktop.sway.replaceDefaultSession = true;

        home-manager = {
          useGlobalPkgs = true;
          useUserPackages = true;
          extraSpecialArgs = { inherit hostConfig; };
          users.smoke = {
            imports = [
              self.homeManagerModules.default
              self.homeManagerModules.hostcfg-feed
            ];
            home = {
              username = "smoke";
              homeDirectory = "/home/smoke";
              stateVersion = "26.05";
            };
            dynamic.desktop = {
              kanshi.config = ./assets/kanshi.config;
              niri.outputs = builtins.readFile ./assets/niri-outputs.kdl;
            };
            # Exercise the browser-bridge policy plumbing.
            programs.firefox.enable = true;
            programs.chromium.enable = true;
          };
        };
      }
    ];
  };

  c = sys.config;
  h = c.home-manager.users.smoke;

  # A few contract assertions on the evaluated config (cheap, and they make
  # regressions in the feeds obvious instead of silent).
  expect =
    name: cond: if cond then true else throw "eval-smoke (${system}): expectation failed: ${name}";
  ok = lib.all (x: x) [
    (expect "both WMs enabled" (c.programs.sway.enable && c.programs.niri.enable))
    (expect "greetd on when SDDM is off" c.services.greetd.enable)
    (expect "sessions: wrapped sway + niri only" (
      lib.sort lib.lessThan (map (p: p.name) c.services.displayManager.sessionPackages)
      == lib.sort lib.lessThan [
        "sway-debug-session"
        "sway-regular-session"
        pkgs.niri.name
      ]
    ))
    (expect "ui.theme.scheme fed" (c.ui.theme.scheme == "nord"))
    (expect "wallpaper fed + enabled" (
      h.dynamic.wallpaper.enable && h.dynamic.wallpaper.file == "wallpaper.png"
    ))
    (expect "keyboard fed to sway" (
      h.wayland.windowManager.sway.config.input."type:keyboard".xkb_layout == "eu"
    ))
    (expect "touchpad fed to sway" (
      h.wayland.windowManager.sway.config.input."type:touchpad".tap == "disabled"
    ))
    (expect "niri kdl rendered with outputs" (
      lib.hasInfix "output \"eDP-1\"" h.xdg.configFile."niri/config.kdl".text
    ))
    (expect "waybar: no leftover placeholders" (
      !(lib.hasInfix "@WB_" h.home.file.".config/waybar/config".text)
      && !(lib.hasInfix "@WB_" h.home.file.".config/waybar/modules.json".text)
    ))
    (expect "waybar: vpn + display modules spliced in" (
      lib.hasInfix "custom/vpn-wg" h.home.file.".config/waybar/config".text
      && lib.hasInfix "custom/display-docked" h.home.file.".config/waybar/config".text
    ))
    (expect "gopass: both stores mounted for the bridge" (
      lib.hasInfix "password-store-b" h.home.file.".local/state/gopass/bridge/.config/gopass/config".text
    ))
    (expect "gopass: firefox policy + chromium force-list" (
      (h.programs.firefox.policies.ExtensionSettings ? "{eec37db0-22ad-4bf1-9068-5ae08df8c7e9}")
      && (lib.any (e: e.id == "kkhfnlkhiapbiehimabddjbimfaijdhk") h.programs.chromium.extensions)
    ))
    (expect "repo-sync: two timers" (
      (h.systemd.user.timers ? "repo-sync-forge-a") && (h.systemd.user.timers ? "repo-sync-forge-b")
    ))
    (expect "kanshi unit present" (h.systemd.user.services ? kanshi))
    (expect "zellij + swaync on" (h.programs.zellij.enable && h.services.swaync.enable))
  ];
in
assert ok;
pkgs.writeText "eval-smoke-${system}" (
  builtins.unsafeDiscardStringContext c.system.build.toplevel.drvPath + "\n"
)
