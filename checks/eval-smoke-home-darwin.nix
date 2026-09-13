# Evaluation smoke test for the macOS path: a standalone home-manager
# configuration for aarch64-darwin importing every home module (evaluated on
# the Linux CI host — nothing is built). The desktop shell self-disables (no
# WM on macOS), theming/tmux/gopass evaluate, and repo-sync must land on
# `launchd.agents` instead of systemd.
{
  self,
  nixpkgs,
  home-manager,
  hostSystem ? "x86_64-linux",
}:
let
  system = "aarch64-darwin";
  inherit (nixpkgs) lib;
  pkgs = import nixpkgs { inherit system; };
  hostPkgs = import nixpkgs { system = hostSystem; };

  hostConfig = self.lib.mkHostConfig {
    raw = {
      gopass = {
        defaultStore = "~/.password-store";
        stores = [ "~/.password-store" ];
      };
      repoSync.gitea = {
        forge = "gitea";
        baseUrl = "https://git.example.com";
        environmentFile = "/Users/smoke/.config/sops-nix/secrets/gitea.env";
        sshPort = 2222;
      };
    };
  };

  hm = home-manager.lib.homeManagerConfiguration {
    inherit pkgs;
    extraSpecialArgs = { inherit hostConfig; };
    modules = [
      self.homeManagerModules.default
      self.homeManagerModules.hostcfg-feed
      {
        home = {
          username = "smoke";
          homeDirectory = "/Users/smoke";
          stateVersion = "26.05";
        };
        # The gopass module enables gpg-agent with pinentry-gnome3 by default; a
        # macOS consumer overrides it like this.
        services.gpg-agent.pinentry.package = pkgs.pinentry_mac;
      }
    ];
  };

  h = hm.config;
  expect =
    name: cond: if cond then true else throw "eval-smoke-home-darwin: expectation failed: ${name}";
  ok = lib.all (x: x) [
    (expect "desktop shell off without a WM" (!h.dynamic.desktop.enable))
    (expect "repo-sync → launchd agent" (h.launchd.agents ? "repo-sync-gitea"))
    (expect "repo-sync agent runs the wrapper" (
      lib.hasInfix "repo-sync-gitea" (lib.head h.launchd.agents."repo-sync-gitea".config.ProgramArguments)
    ))
    (expect "gopass CLI wrapper present, wofi launcher absent on macOS" (
      lib.any (p: (p.name or "") == "gopass-selected") h.home.packages
      && !lib.any (p: (p.name or "") == "gopass-launcher") h.home.packages
    ))
    (expect "macOS pinentry default" (
      h.services.gpg-agent.pinentry.package.pname or "" == "pinentry-mac"
    ))
    (expect "tmux on" h.programs.tmux.enable)
  ];
in
assert ok;
hostPkgs.writeText "eval-smoke-home-darwin" (
  builtins.unsafeDiscardStringContext h.home.activationPackage.drvPath + "\n"
)
