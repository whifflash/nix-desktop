{
  description = "nix-desktop — shared Wayland desktop shell (sway/niri/waybar/swaync), token theming with a runtime switcher, gopass (store switcher, browser bridge, SSH askpass), tmux session persistence and a forge-agnostic repo-sync, as NixOS + home-manager modules";

  inputs = {
    # Stable is the primary target; unstable is only used to double-check the
    # module API surface in `checks`. Consumers pass their OWN pkgs/lib to the
    # modules — these inputs never leak into a consumer's closure.
    nixpkgs.url = "github:NixOS/nixpkgs/nixos-26.05";
    nixpkgs-unstable.url = "github:NixOS/nixpkgs/nixos-unstable";

    home-manager = {
      url = "github:nix-community/home-manager/release-26.05";
      inputs.nixpkgs.follows = "nixpkgs";
    };
    home-manager-unstable = {
      url = "github:nix-community/home-manager";
      inputs.nixpkgs.follows = "nixpkgs-unstable";
    };

    flake-parts = {
      url = "github:hercules-ci/flake-parts";
      inputs.nixpkgs-lib.follows = "nixpkgs";
    };
    treefmt-nix = {
      url = "github:numtide/treefmt-nix";
      inputs.nixpkgs.follows = "nixpkgs";
    };
  };

  outputs =
    inputs@{
      self,
      flake-parts,
      nixpkgs,
      ...
    }:
    flake-parts.lib.mkFlake { inherit inputs; } {
      systems = [
        "x86_64-linux"
        "aarch64-linux"
        "aarch64-darwin"
      ];

      imports = [ inputs.treefmt-nix.flakeModule ];

      flake = {
        # config.toml normaliser: `lib.mkHostConfig { raw; extraDefaults; }`
        # (see lib/hostcfg.nix and docs/CONFIG-TOML.md).
        lib = import ./lib/hostcfg.nix { inherit (nixpkgs) lib; };

        nixosModules = {
          # ui.theme / ui.waybar option decls, system Stylix bridge, and the
          # sway / niri / wayland-common desktop modules (self-gating).
          default = import ./nixos;
          ui = import ./nixos/ui;
          desktop = import ./nixos/desktop;
          # config.toml → options. Needs `hostConfig` in specialArgs.
          hostcfg-feed = import ./nixos/hostcfg-feed.nix;
        };

        homeManagerModules = {
          default = import ./home;
          themes = import ./home/themes;
          desktop = import ./home/desktop;
          apps = import ./home/apps;
          repo-sync = import ./home/services/repo-sync.nix;
          # config.toml → options. Needs `hostConfig` in extraSpecialArgs.
          hostcfg-feed = import ./home/hostcfg-feed.nix;
        };
      };

      perSystem =
        {
          pkgs,
          lib,
          system,
          ...
        }:
        {
          # `nix fmt`: nixfmt (RFC 166) for Nix, shfmt for shell — the same
          # formatters the consumers use, so shared files never churn on format.
          treefmt = {
            projectRootFile = "flake.nix";
            programs = {
              nixfmt.enable = true;
              shfmt.enable = true;
            };
          };

          devShells.default = pkgs.mkShell {
            packages = with pkgs; [
              nixfmt
              shfmt
              shellcheck
              statix
              deadnix
            ];
          };

          checks = {
            statix = pkgs.runCommand "statix" { nativeBuildInputs = [ pkgs.statix ]; } ''
              statix check ${self}
              touch $out
            '';
            deadnix = pkgs.runCommand "deadnix" { nativeBuildInputs = [ pkgs.deadnix ]; } ''
              deadnix --fail ${self}
              touch $out
            '';
            # The sync engine is shellchecked at build time by writeShellApplication;
            # evaluate+build just that derivation so `nix flake check` covers it.
            repo-sync-script = pkgs.writeShellApplication {
              name = "repo-sync";
              runtimeInputs = with pkgs; [
                coreutils
                curl
                jq
                git
                openssh
                gnused
                gnugrep
              ];
              text = builtins.readFile ./home/services/repo-sync/sync.sh;
            };
          }
          // lib.optionalAttrs (system == "x86_64-linux") {
            # Instantiate a full stub NixOS+HM system on both channels (eval only).
            eval-smoke-stable = import ./checks/eval-smoke.nix {
              inherit self system;
              inherit (inputs) nixpkgs home-manager;
            };
            eval-smoke-unstable = import ./checks/eval-smoke.nix {
              inherit self system;
              nixpkgs = inputs.nixpkgs-unstable;
              home-manager = inputs.home-manager-unstable;
            };
            # The macOS home path (launchd repo-sync, desktop shell inert),
            # evaluated for aarch64-darwin from this Linux host.
            eval-smoke-home-darwin = import ./checks/eval-smoke-home-darwin.nix {
              inherit self;
              inherit (inputs) nixpkgs home-manager;
              hostSystem = system;
            };
          };
        };
    };
}
