{
  config,
  lib,
  ...
}:
let
  home = config.home.homeDirectory;
in
{
  # Point the theme-consuming apps at the live (runtime-swappable) theme files
  # generated per-scheme by tokens.nix. The files are seeded and retargeted by
  # tokens.nix's activation + theme-set; here we only wire each app to read them.

  # Alacritty: import the live colours file. live_config_reload (default on)
  # re-reads it when theme-set retargets the symlink — no restart needed.
  # (Stylix's own alacritty target is disabled in hm-stylix-bridge.nix so it
  # doesn't bake a static [colors] block that would override this import.)
  programs.alacritty = {
    enable = true;
    settings.general.import = [ "${home}/.config/alacritty/colors.toml" ];
  };

  # tmux config lives in home/tmux.nix (imported unconditionally); append the
  # source line here — Sway-gated — so it is only added when the theme system is
  # present. `-q` keeps a missing file quiet; theme-set re-sources it on switch.
  programs.tmux.extraConfig = lib.mkAfter ''
    source-file -q ~/.config/tmux/theme.conf
  '';

  # Zed: the "dynamic-tokenized-theme" theme file (~/.config/zed/themes/dynamic-tokenized-theme.json)
  # is a symlink swapped per scheme, and Zed hot-reloads its themes dir. Zed's
  # settings.json is user-writable, so only seed the theme selection when the
  # file doesn't exist yet — existing users add  "theme": "dynamic-tokenized-theme"  once.
  home.activation.zedThemeSelect = lib.hm.dag.entryAfter [ "writeBoundary" ] ''
    zs="$HOME/.config/zed/settings.json"
    mkdir -p "$(dirname "$zs")"
    if [ ! -e "$zs" ]; then
      printf '{\n  "theme": "dynamic-tokenized-theme"\n}\n' > "$zs"
    fi
  '';
}
