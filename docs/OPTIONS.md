# The consumer contract

Everything the shared modules read. Consumers set these (directly, or through `config.toml` via the
`hostcfg-feed` modules — the "TOML" column names the key that feeds each option). Modules never
read anything else from the host.

## NixOS options (`nixosModules.default`)

| Option | Type / default | TOML | Notes |
|---|---|---|---|
| `ui.theme.scheme` | str, `catppuccin-macchiato` | `[theme] scheme` | palette in `home/themes/palettes/` |
| `ui.theme.wallpapersDir` | nullOr path, `null` | — (nix path) | directory in *your* repo |
| `ui.theme.wallpaper` | nullOr str, `null` | `[theme] wallpaperEnable` + `wallpaperFile` | `null` = no wallpaper anywhere |
| `ui.theme.wallpaperMode` | enum fill/fit/stretch/tile/center, `fill` | `[theme] wallpaperMode` | |
| `ui.theme.swaylock.image` | nullOr path, `null` | — | defaults to the wallpaper |
| `ui.theme.stylix.enable` | bool, `false` | `[theme] stylix` | needs the stylix modules imported by the consumer |
| `ui.waybar.{batteryName,networkInterface,tempHwmonPath,weatherLocation}` | str | `[waybar] …` | machine facts for the bar |
| `programs.sway.enable`, `programs.niri.enable` | upstream | `[features] sway`, `niri` | the WM switches; both may be on |
| `desktop.sway.replaceDefaultSession` | bool, `false` | — | `true` drops the stock `sway` session in favour of the wrapped `sway-regular`/`sway-debug` (avoids a greeter teardown quirk). Keep `false` if anything references the session name `sway` (e.g. Jovian). |
| `desktop.wayland.{enable,sessionCommands,extraPackages,extraSessionVariables}` | — | — | set by the WM modules; greetd/tuigreet is provided unless `services.displayManager.sddm.enable` |

## home-manager options (`homeManagerModules.default`)

| Option | Type / default | TOML | Notes |
|---|---|---|---|
| `dynamic.theme.scheme` | nullOr str, `null` → `osConfig.ui.theme.scheme` | — | build-time default; a runtime `theme-switcher` choice wins |
| `dynamic.theme.write{Waybar,Wofi,Swaync}Palette`, `writeShellEnv`, `writeGtkOverride` | bool, `true` | — | which live theme files to seed |
| `dynamic.wallpaper.{enable,dir,file,mode,swaylockImage,perOutput,linkToPictures}` | defaults from `osConfig.ui.theme.*`; `enable` = desktop on ∧ wallpaper set | — | |
| `dynamic.desktop.enable` | bool, on when host enables sway or niri | — | gates the whole shell |
| `dynamic.desktop.terminal` | package, `pkgs.alacritty` | — | |
| `dynamic.desktop.keyboard.{layout,variant,options}` | str, `us`/``/`` | `[desktop] keyboardLayout/Variant/Options` | applied to Sway and niri |
| `dynamic.desktop.touchpad.tap` | bool, `true` | `[desktop] touchpadTap` | |
| `dynamic.desktop.scratchpad.{command,title,appId}` | tmux `scratch` session | `[desktop] scratchpadCommand` | the drop-down terminal (Mod+i) |
| `dynamic.desktop.waybar.vpn.{wg,ovpn}` | nullOr str, `null` | `[desktop] waybarVpnWg/Ovpn` | NM connection names; null omits the toggle |
| `dynamic.desktop.waybar.displayProfiles.{docked,laptop}` | nullOr str, `null` | `[desktop] waybarDisplayDocked/Laptop` | kanshi profile names; needs `kanshi.config` |
| `dynamic.desktop.kanshi.config` | nullOr path, `null` | — (nix path) | machine-specific profiles; null = no kanshi |
| `dynamic.desktop.niri.outputs` | lines, `` | — (nix path via `readFile`) | raw KDL `output {}` blocks |
| `dynamic.desktop.niri.workspaces` | list, `1`–`7` | — | |
| `dynamic.gopass.{stores,defaultStore}` | list/str, `~/.password-store` | `[gopass] stores/defaultStore` | all stores are searched by the bridge + SSH askpass |
| `dynamic.gopass.browserBridge.enable` | bool, `true` | — | installs gopassbridge into enabled `programs.firefox` / `programs.chromium` |
| `services.repo-sync.instances.<name>.{forge,baseUrl,destDir,environmentFile,sshHost,sshPort,intervalSec,randomizedDelaySec,logLevel,stateDir,enable}` | see module | `[repoSync.<name>] …` | `environmentFile` exports `TOKEN=…` at run time |

## Commands the modules put on `PATH`

`theme-switcher` / `theme-set <scheme>` / `theme-current`, `gopass-launcher`, `gopass-switcher`,
`gopass-current-store`, `gopass-selected`, `gopass-ssh-load <keyfile> [<entry>]`,
`gopass-ssh-askpass`, `repo-sync` and `repo-sync-<instance>`.

SSH pinning (which key for which host) stays consumer data — in `~/.ssh/config` or
`programs.ssh.extraConfig`:

```
Match host git.example.com exec "gopass-ssh-load identities/example_git ssh/example/git || true"
    IdentityFile ~/.ssh/identities/example_git
    IdentitiesOnly yes
```
