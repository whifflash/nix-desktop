# nix-desktop

Shared desktop layer for NixOS + home-manager, consumed as a flake input by more than one
machine repo so the code lives in exactly one place:

- **Wayland desktop shell** — Sway and niri (both may be enabled; the greeter offers a chooser),
  Waybar (window count, VPN toggles, kanshi display buttons), swaync notifications, swaylock,
  kanshi, flameshot, a zellij-backed drop-down terminal.
- **Token theming with a runtime switcher** — one palette (`home/themes/palettes/*.nix`) drives
  Sway colours, Waybar, wofi, swaync, alacritty, zellij, zed, GTK and Stylix; `theme-switcher`
  flips all of them live without a rebuild.
- **gopass** — store switcher, wofi launcher, browser bridge searching *all* stores (Firefox +
  Chromium auto-install), SSH key passphrases pulled from gopass via `SSH_ASKPASS`.
- **zellij** — session persistence via native serialization, with the drop-down session's
  stable tabs DECLARED in config.toml (`[[zellij.tabs]]`) rather than captured, so tab
  names survive a reboot. Ad-hoc tabs return via zellij's own serialization.
- **repo-sync** — periodic "clone everything my token can see" for Gitea / GitLab / GitHub
  (systemd user timer on Linux, launchd agent on macOS).
- **`config.toml` knobs** — a small normaliser (`lib.mkHostConfig`) plus two feed modules that
  turn a per-host TOML file into the options above.

Targets `nixos-26.05` / `home-manager release-26.05`; `nix flake check` also evaluates
everything against current unstable.

## Consuming

```nix
# flake.nix
inputs.nix-desktop.url = "github:whifflash/nix-desktop";

# NixOS
modules = [
  inputs.nix-desktop.nixosModules.default      # ui.* options, sway/niri/wayland-common
  inputs.nix-desktop.nixosModules.hostcfg-feed # only if you use config.toml (needs specialArgs.hostConfig)
];
# home-manager (as a NixOS module or nix-darwin module)
home-manager.sharedModules = [
  inputs.nix-desktop.homeManagerModules.default      # themes, desktop, zellij, gopass, repo-sync
  inputs.nix-desktop.homeManagerModules.hostcfg-feed # only with config.toml (needs extraSpecialArgs.hostConfig)
];
```

Then either write a `config.toml` (see [docs/CONFIG-TOML.md](docs/CONFIG-TOML.md)) and pass
`hostConfig = inputs.nix-desktop.lib.mkHostConfig { raw = builtins.fromTOML (builtins.readFile ./hosts/<h>/config.toml); }`
through `specialArgs` / `extraSpecialArgs`, or set the options directly
([docs/OPTIONS.md](docs/OPTIONS.md)). Two things are always plain nix on the consumer side because
they are paths into *your* repo: `ui.theme.wallpapersDir` and the machine files
`dynamic.desktop.kanshi.config` / `dynamic.desktop.niri.outputs`.

Everything self-gates: import the modules unconditionally, then switch WMs with
`programs.sway.enable` / `programs.niri.enable` (or `[features]` in TOML).

## Developing

```sh
nix fmt            # nixfmt + shfmt
nix flake check    # statix, deadnix, shellcheck (repo-sync), eval-smoke on 26.05 AND unstable
```

In a consumer, iterate against a local checkout without pushing:

```sh
nixos-rebuild switch --flake . --override-input nix-desktop path:../nix-desktop
```

(The consumer repos' Taskfiles apply that override automatically when `../nix-desktop` exists.)
Push here, then `nix flake update nix-desktop` in each consumer when ready — consumers may lag
behind on purpose.

## Layout

```
lib/hostcfg.nix            mkHostConfig: TOML → hostConfig (shared defaults + your extraDefaults)
nixos/ui/                  ui.theme, ui.waybar option decls; system Stylix bridge
nixos/desktop/             wayland-common (tooling, keyring, polkit, greetd fallback), sway, niri
nixos/hostcfg-feed.nix     hostConfig → ui.*, programs.{sway,niri}.enable
home/themes/               tokens, palette-lib, seed, theme-switcher, per-app wiring, palettes/
home/desktop/              options (dynamic.desktop.*), sway, niri, waybar, swaync, swaylock, kanshi, flameshot
home/apps/                 zellij, gopass
home/services/repo-sync    module + forge-agnostic sync.sh
home/hostcfg-feed.nix      hostConfig → dynamic.*, services.repo-sync
checks/                    eval-smoke stub system + assets
```
