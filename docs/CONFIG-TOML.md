# config.toml — the shared schema

`lib.mkHostConfig { raw; extraDefaults ? {}; }` fills these defaults (from `lib/hostcfg.nix`) under
the raw TOML, then your own `extraDefaults` for repo-specific sections. The result is what the
`hostcfg-feed` modules read (`specialArgs.hostConfig` / `extraSpecialArgs.hostConfig`).

Only scalars live in TOML. Anything that is a **path into your repo** stays nix:
`ui.theme.wallpapersDir`, `ui.theme.swaylock.image`, `dynamic.desktop.kanshi.config`,
`dynamic.desktop.niri.outputs`, and `desktop.sway.replaceDefaultSession`.

```toml
[features]
sway = true            # register a Sway login session
niri = false           # register a niri login session (both may be true)

[theme]
scheme          = "catppuccin-macchiato"   # home/themes/palettes/<name>.nix
wallpaperEnable = false
wallpaperFile   = "default.jpg"            # relative to ui.theme.wallpapersDir (nix)
wallpaperMode   = "fill"                   # fill | fit | stretch | tile | center
stylix          = false

[desktop]
keyboardLayout      = "us"
keyboardVariant     = ""
keyboardOptions     = ""                   # e.g. "caps:super,terminate:ctrl_alt_bksp"
touchpadTap         = true
scratchpadCommand   = ""                   # "" = persistent tmux "scratch" session
waybarVpnWg         = ""                   # NetworkManager connection name; "" = no button
waybarVpnOvpn       = ""
waybarDisplayDocked = ""                   # kanshi profile names; "" = no display buttons
waybarDisplayLaptop = ""

[waybar]
batteryName      = "BAT0"                  # ls /sys/class/power_supply
networkInterface = "wlan0"
weatherLocation  = ""                      # "" → wttr.in auto-locates by IP
tempHwmonPath    = "/sys/class/hwmon/hwmon0/temp1_input"

[gopass]
defaultStore = "~/.password-store"
stores       = ["~/.password-store"]       # absolute, ~/…, or relative to $HOME

# One table per repo-sync instance (omit the section entirely for none).
[repoSync.work]
forge              = "gitlab"              # gitea | gitlab | github
baseUrl            = "https://gitlab.example.com"
destDir            = "/home/me/git/gitlab.example.com"   # default: ~/git/<name>
environmentFile    = "/run/secrets/gitlab-token.env"     # exports TOKEN=…
sshPort            = 22
intervalSec        = 3600
randomizedDelaySec = 600
logLevel           = "INFO"
```

## Wiring (single host, TOML as a flake input — the "work" pattern)

```nix
hostConfig = inputs.nix-desktop.lib.mkHostConfig {
  raw = builtins.fromTOML (builtins.readFile "${inputs.hostcfg}/config.toml");
  extraDefaults = { features.docker = false; vpn = { … }; };   # your sections
};
```

## Wiring (multi-host, TOML per host in-tree — the "personal" pattern)

```nix
mkHost = name: let
  tomlFile = ./hosts + "/${name}/config.toml";
  hostConfig = inputs.nix-desktop.lib.mkHostConfig {
    raw = if builtins.pathExists tomlFile then builtins.fromTOML (builtins.readFile tomlFile) else { };
  };
in nixpkgs.lib.nixosSystem {
  specialArgs = { inherit inputs hostConfig; };
  modules = [ … inputs.nix-desktop.nixosModules.default inputs.nix-desktop.nixosModules.hostcfg-feed
    { home-manager.extraSpecialArgs = { inherit hostConfig; };
      home-manager.sharedModules = [ inputs.nix-desktop.homeManagerModules.default inputs.nix-desktop.homeManagerModules.hostcfg-feed ]; } ];
};
```

A host without a `config.toml` gets the defaults above: no WM, no desktop shell, one gopass store,
no repo-sync — i.e. the modules are inert on a headless machine.
