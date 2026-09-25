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

## Zellij keybindings

The drop-down runs zellij, driven through zellij's **built-in `tmux` mode** — a prefix-style
island in an otherwise modal keymap. `home/apps/zellij.nix` only retargets the trigger at
`Ctrl-a` and fills the gaps its default set omits; none of this fights zellij's design.

| Key | Action |
|---|---|
| `Ctrl-a` | enter tmux mode (zellij's own trigger is `Ctrl-b`) |
| `Ctrl-a` `Ctrl-a` | send a literal `Ctrl-a` through (tmux's `send-prefix`) |
| `Ctrl-a` `\|` / `-` | split right / down (zellij's own `"` and `%` also work) |
| `Ctrl-a` `c` / `x` | new tab / close pane |
| `Ctrl-a` `,` / `r` | rename **tab** / rename **pane** |
| `Ctrl-a` `h` `j` `k` `l` | focus pane |
| `Ctrl-a` `H` `J` `K` `L` | resize pane (stays in mode, so repeats work like tmux's `bind -r`) |
| `Ctrl-a` `n` / `p` | next / previous tab |
| `Ctrl-a` `z` / `d` | fullscreen / detach |

Tuning: `dynamic.zellij.tmuxMode.prefix`, `.freeShellKeys`, `.bar`
(`default` | `compact` | `none`).

### Ctrl keys zellij claims — and why we hand them back

Zellij's modal defaults bind a lot of `Ctrl` keys, and a `keybinds` block **merges** with
those defaults unless `clear-defaults=true`. Anything left bound is swallowed before the
shell — or a nested program — ever sees it.

`freeShellKeys` is a list (so individual keys can be kept) and unbinds:

| Key | Would otherwise shadow |
|---|---|
| `Ctrl-p` / `Ctrl-n` | shell history |
| `Ctrl-s` | forward-search |
| `Ctrl-t` | fzf's file widget |
| `Ctrl-o` | operate-and-get-next |
| `Ctrl-h` | Backspace, on many terminals |

The same applies to **nested multiplexers**, which need their own prefix key released or
zellij consumes it first. `Ctrl-b` is therefore unbound whenever it is not itself the
configured prefix — that is herdr's prefix inside a nix-los guest, so releasing it keeps
`Ctrl-b <key>` working there.

That leaves `Ctrl-a` (the prefix) and `Ctrl-g` (lock mode) as the only `Ctrl` keys zellij
claims — the short list to check first when a nested tool stops receiving its keys.

### Session layout

Tabs are **declared**, not captured: `[[zellij.tabs]]` in `config.toml` renders into
`layouts/<session>.kdl`, so tab names cannot drift or go missing on restore. Ad-hoc tabs you
create by hand still return, via zellij's own `session_serialization`. Two notes worth keeping:

- Supplying *any* custom layout replaces zellij's built-in one, and the tab/status bars live
  in that layout as plugin panes — hence the explicit `default_tab_template` (`bar` option).
  Without it a session comes up with no tab names and no overview at all.
- Two names differ from zellij's published docs as of 0.45.1: scrollback serialization is
  `serialize_pane_viewport` (docs say `pane_viewport_serialization`), and theme
  `exit_code_success`/`_error` take the full six colour keys, not just `base`.
  `zellij setup --check` validates semantics, not just KDL syntax — worth running after any
  config or theme change.

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
