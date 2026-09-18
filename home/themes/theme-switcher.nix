{
  config,
  lib,
  pkgs,
  ...
}:
let
  # Runtime theme switching for the Sway desktop shell + daily apps: Waybar,
  # wofi, swaync, live Sway window colours, alacritty, tmux, zed, and a
  # best-effort GTK override (nemo). Every palette is pre-rendered by tokens.nix
  # under ~/.config/theme/palettes/<name>/; the live files each app reads are
  # symlinks into that tree, so switching == retarget the symlinks + reload.
  #
  # Reload story per app (no full restart needed for the first three):
  #   alacritty — live_config_reload watches the imported colours file
  #   zed       — watches ~/.config/zed/themes and hot-reloads the active theme
  #   zellij    — theme file is swapped by ./seed.nix; zellij has no reload
  #               action, so a running session picks it up on next start
  #   waybar    — auto-restarts via launch_waybar.sh when palette.css changes
  #   swaync    — `swaync-client --reload-css`
  #   wofi      — nothing: spawned fresh per launch, re-reads style.css each time
  #   gtk/nemo  — best-effort gsettings nudge; most reliably updates on restart
  #
  # Modelled on the gopass store switcher (home/gopass.nix): a wofi menu writes
  # the choice to a state file, and activation re-seeds from that state file so a
  # rebuild never clobbers a live choice.
  #
  # NOTE: GTK/Qt/Firefox theming is really owned by Stylix (baked at build time,
  # from config.toml's [theme].scheme). The GTK override here is a best-effort
  # top-up; for guaranteed GTK consistency set [theme].scheme and `task switch`.
  homeDir = config.home.homeDirectory;
  cfgDir = "${homeDir}/.config";

  palettesDir = "${cfgDir}/theme/palettes";
  activeFile = "${cfgDir}/theme/active-scheme";
  stateFile = "${homeDir}/.local/state/theme/current-scheme";

  gtkOverride = config.dynamic.theme.writeGtkOverride;

  # Build-time default (resolved scheme name), used when no state file exists.
  defaultScheme = config.dynamic.theme.paletteName;

  themeCurrent = pkgs.writeShellApplication {
    name = "theme-current";
    runtimeInputs = [ pkgs.coreutils ];
    text = ''
      set -euo pipefail
      state_file=${lib.escapeShellArg stateFile}
      default=${lib.escapeShellArg defaultScheme}
      if [ -f "$state_file" ]; then cat "$state_file"; else printf '%s\n' "$default"; fi
    '';
  };

  themeSet = pkgs.writeShellApplication {
    name = "theme-set";
    runtimeInputs = [
      pkgs.coreutils
      pkgs.libnotify
      pkgs.sway
      pkgs.swaynotificationcenter
      pkgs.glib # gsettings
    ];
    text = ''
      set -euo pipefail

      palettes=${lib.escapeShellArg palettesDir}
      state_file=${lib.escapeShellArg stateFile}
      active_file=${lib.escapeShellArg activeFile}

      # --colors-only just re-applies Sway window colours (used by the Sway
      # startup hook, since `swaymsg reload` reverts to the baked config colours).
      colors_only=false
      if [ "''${1:-}" = "--colors-only" ]; then
        colors_only=true
        shift
      fi

      scheme="''${1:-}"
      if [ -z "$scheme" ]; then
        echo "usage: theme-set [--colors-only] <scheme>" >&2
        exit 1
      fi

      pal="$palettes/$scheme"
      if [ ! -d "$pal" ]; then
        notify-send "Theme" "Unknown scheme: $scheme" 2>/dev/null || true
        echo "theme-set: unknown scheme: $scheme" >&2
        exit 1
      fi

      if [ "$colors_only" = false ]; then
        mkdir -p "$(dirname "$state_file")"
        printf '%s\n' "$scheme" > "$state_file"

        # Retarget the live theme symlinks (shared mapping — see ./seed.nix).
        ${import ./seed.nix {
          inherit lib;
          cfg = config.dynamic.theme;
        }}

        printf '%s\n' "$scheme" > "$active_file"
      fi

      # Apply Sway window colours live. Guarded on SWAYSOCK so it is a harmless
      # no-op when run outside a Sway session.
      if command -v swaymsg >/dev/null 2>&1 && [ -n "''${SWAYSOCK:-}" ]; then
        while read -r cmd; do
          [ -n "$cmd" ] || continue
          # shellcheck disable=SC2086
          swaymsg $cmd >/dev/null || true
        done < "$pal/sway.colors"
      fi

      if [ "$colors_only" = false ]; then
        # swaync reloads its CSS on demand; Waybar auto-restarts via
        # launch_waybar.sh once palette.css (followed symlink) changes hash.
        swaync-client --reload-css 2>/dev/null || true

        # Alacritty (live_config_reload) and Zed (themes watcher) re-read on
        # their own. Zellij has no reload-config action, so its swapped theme
        # file (./seed.nix) applies to the next session start.
        ${lib.optionalString gtkOverride ''
          # Best-effort nudge so running GTK apps (e.g. nemo) re-read gtk.css.
          if command -v gsettings >/dev/null 2>&1; then
            cur="$(gsettings get org.gnome.desktop.interface gtk-theme 2>/dev/null | tr -d "'\"" || true)"
            if [ -n "$cur" ]; then
              gsettings set org.gnome.desktop.interface gtk-theme "Adwaita" 2>/dev/null || true
              gsettings set org.gnome.desktop.interface gtk-theme "$cur" 2>/dev/null || true
            fi
          fi
        ''}

        notify-send "Theme" "Switched to: $scheme" 2>/dev/null || true
      fi
    '';
  };

  themeSwitcher = pkgs.writeShellApplication {
    name = "theme-switcher";
    runtimeInputs = [
      pkgs.coreutils
      pkgs.findutils
      pkgs.libnotify
      pkgs.wofi
      themeCurrent
      themeSet
    ];
    text = ''
      set -euo pipefail

      palettes=${lib.escapeShellArg palettesDir}
      if [ ! -d "$palettes" ]; then
        notify-send "Theme" "No palettes found at $palettes" 2>/dev/null || true
        exit 1
      fi

      current="$(theme-current)"

      # One scheme per line, the active one flagged; the marker is stripped
      # from the selection before it reaches theme-set.
      choice="$(
        find "$palettes" -mindepth 1 -maxdepth 1 -type d -printf '%f\n' \
          | sort \
          | while read -r name; do
              if [ "$name" = "$current" ]; then
                printf '%s  ●\n' "$name"
              else
                printf '%s\n' "$name"
              fi
            done \
          | wofi --dmenu --matching=fuzzy --insensitive -p 'theme'
      )" || exit 0

      choice="''${choice%%  ●}"
      [ -n "$choice" ] || exit 0

      theme-set "$choice"
    '';
  };
in
{
  # The switcher drives sway/swaync/wofi — a Linux Wayland desktop. The
  # pre-rendered palettes (tokens.nix) and per-app wiring (apps.nix) still apply
  # on macOS; only the live-switch tooling is skipped there.
  config = lib.mkIf pkgs.stdenv.hostPlatform.isLinux {
    home.packages = [
      themeCurrent
      themeSet
      themeSwitcher
    ];

    xdg.desktopEntries.theme-switcher = {
      name = "Theme Switcher";
      exec = "${themeSwitcher}/bin/theme-switcher";
      terminal = false;
      categories = [ "Utility" ];
    };
  };
}
