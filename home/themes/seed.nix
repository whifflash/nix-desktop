# Shell snippet that (re)points the live theme files at "$pal" — the active
# scheme's dir under ~/.config/theme/palettes/<name>. Shared by tokens.nix's
# activation (build-time seed) and theme-switcher.nix's theme-set (runtime
# switch) so the symlink mapping lives in exactly one place. Callers must have a
# shell variable `pal` set to the scheme dir before interpolating this.
{ lib, cfg }:
let
  link = target: artifact: ''
    mkdir -p "$(dirname "${target}")"
    ln -sfn "$pal/${artifact}" "${target}"
  '';
in
lib.concatStrings [
  (lib.optionalString cfg.writeWaybarPalette (link "$HOME/.config/waybar/palette.css" "palette.css"))
  # wofi reads style.css directly (no daemon, no @import), so the live file is the
  # full self-contained stylesheet (tokens.nix' wofi.css), swapped on theme-set.
  (lib.optionalString cfg.writeWofiPalette (link "$HOME/.config/wofi/style.css" "wofi.css"))
  (lib.optionalString cfg.writeSwayncPalette (link "$HOME/.config/swaync/palette.css" "palette.css"))
  (lib.optionalString cfg.writeShellEnv (link "$HOME/.config/theme/env" "env"))
  # Per-app live theme files (alacritty/tmux/zed reload on their own).
  (link "$HOME/.config/alacritty/colors.toml" "alacritty.toml")
  (link "$HOME/.config/tmux/theme.conf" "tmux.conf")
  (link "$HOME/.config/zed/themes/dynamic-tokenized-theme.json" "zed.json")
  (link "$HOME/.config/zellij/themes/dynamic-tokenized-theme.kdl" "zellij.kdl")
  (lib.optionalString cfg.writeGtkOverride ''
    for gtk_css in "$HOME/.config/gtk-3.0/gtk.css" "$HOME/.config/gtk-4.0/gtk.css"; do
      # Never clobber a home-manager/Stylix-managed gtk.css (store symlink).
      case "$(readlink "$gtk_css" 2>/dev/null || true)" in
        /nix/store/*) : ;;
        *)
          mkdir -p "$(dirname "$gtk_css")"
          ln -sfn "$pal/gtk.css" "$gtk_css"
          ;;
      esac
    done
  '')
]
