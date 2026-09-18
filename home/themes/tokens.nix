{
  lib,
  config,
  osConfig ? { },
  ...
}:
let
  cfg = config.dynamic.theme;

  # Shared palette discovery/loading + base16 map (see ./palette-lib.nix).
  palettes = import ./palette-lib.nix { inherit lib; };
  inherit (palettes) available loadPalette;

  # Host-level choice via the shared option interface (ui.theme.scheme, fed by
  # the consumer — e.g. from config.toml); guarded so standalone HM evals too.
  hostScheme = lib.attrByPath [ "ui" "theme" "scheme" ] "catppuccin-macchiato" osConfig;
  chosenName = if cfg.scheme != null then cfg.scheme else hostScheme;
  palette = loadPalette chosenName;
  T = palette.tokens;

  # ── generators (each takes a palette's semantic token set) ──────────────
  mkGtkPalette =
    tokens:
    let
      names = lib.sort (a: b: a < b) (builtins.attrNames tokens);
      lines = map (k: "@define-color ${k} ${tokens.${k}};") names;
    in
    lib.concatStringsSep "\n" lines + "\n";

  mkEnv =
    tokens:
    let
      names = lib.sort (a: b: a < b) (builtins.attrNames tokens);
      lines = map (k: "export THEME_${lib.toUpper k}=${tokens.${k}}") names;
    in
    lib.concatStringsSep "\n" lines + "\n";

  # Sway window colours as runtime `swaymsg` commands (one `client.*` per line),
  # derived from the same role table as the baked config (sway-colors.nix) so the
  # live form can never drift from a rebuild. `g` falls back so an incomplete
  # palette never throws.
  mkSwayColors =
    tokens:
    let
      g = n: tokens.${n} or "#555555";
      roles = import ./sway-color-roles.nix;
      line = _: r: "client.${r.swayClass} " + lib.concatStringsSep " " (map g r.roles);
    in
    lib.concatStringsSep "\n" (lib.mapAttrsToList line roles) + "\n";

  # 16-colour ANSI mapping derived from the semantic tokens, shared by the
  # terminal-ish targets (alacritty, tmux, and zed's integrated terminal).
  mkAnsi = t: {
    inherit (t) bg fg;
    black = t.surface;
    red = t.error;
    green = t.success;
    yellow = t.warning;
    blue = t.hint;
    magenta = t.secondary;
    cyan = t.primary;
    white = t.muted;
    brightBlack = t.overlay;
    brightRed = t.accent1;
    brightGreen = t.success;
    brightYellow = t.warning;
    brightBlue = t.primary;
    brightMagenta = t.accent3;
    brightCyan = t.accent2;
    brightWhite = t.fg;
  };

  # Alacritty colours (TOML). Imported by ~/.config/alacritty/alacritty.toml;
  # Alacritty's live_config_reload re-reads it when the symlink is retargeted.
  mkAlacritty =
    t:
    let
      a = mkAnsi t;
    in
    ''
      # Dynamic tokenized theme — generated from palette tokens.
      [colors.primary]
      background = "${t.bg}"
      foreground = "${t.fg}"

      [colors.cursor]
      text   = "${t.bg}"
      cursor = "${t.primary}"

      [colors.selection]
      text       = "CellForeground"
      background = "${t.surfaceAlt}"

      [colors.normal]
      black   = "${a.black}"
      red     = "${a.red}"
      green   = "${a.green}"
      yellow  = "${a.yellow}"
      blue    = "${a.blue}"
      magenta = "${a.magenta}"
      cyan    = "${a.cyan}"
      white   = "${a.white}"

      [colors.bright]
      black   = "${a.brightBlack}"
      red     = "${a.brightRed}"
      green   = "${a.brightGreen}"
      yellow  = "${a.brightYellow}"
      blue    = "${a.brightBlue}"
      magenta = "${a.brightMagenta}"
      cyan    = "${a.brightCyan}"
      white   = "${a.brightWhite}"
    '';

  # tmux status/pane colours. Sourced by tmux; theme-set re-applies live via
  # `tmux source-file`. No powerline glyphs so it needs no special font.
  mkTmux = t: ''
    # Dynamic tokenized theme — generated from palette tokens.
    set -g pane-border-style "fg=${t.border}"
    set -g pane-active-border-style "fg=${t.primary}"
    set -g message-style "fg=${t.fg},bg=${t.surface}"
    set -g message-command-style "fg=${t.fg},bg=${t.surface}"
    set -g mode-style "fg=${t.bg},bg=${t.primary}"
    set -g status-style "fg=${t.muted},bg=${t.bgAlt}"
    set -g status-left "#[fg=${t.bg},bg=${t.primary},bold] #S #[default] "
    set -g status-right "#[fg=${t.fg},bg=${t.surface}] %Y-%m-%d %H:%M "
    setw -g window-status-style "fg=${t.muted},bg=${t.bgAlt}"
    setw -g window-status-current-style "fg=${t.bg},bg=${t.primary},bold"
    setw -g window-status-format " #I:#W "
    setw -g window-status-current-format " #I:#W "
  '';

  # Zellij theme (KDL). Same trick as the Zed theme below: a FIXED theme name
  # whose file is swapped per scheme, so config.kdl pins `theme` once and only
  # the symlink moves (see ./seed.nix).
  #
  # Zellij takes DECIMAL rgb triples ("fg 202 211 245"), not hex, so the tokens
  # are converted here. Colour roles reuse mkAnsi's mapping so the terminal
  # colours inside a Zellij pane match alacritty/tmux/zed.
  hexToInt =
    h:
    let
      digit =
        c:
        {
          "0" = 0;
          "1" = 1;
          "2" = 2;
          "3" = 3;
          "4" = 4;
          "5" = 5;
          "6" = 6;
          "7" = 7;
          "8" = 8;
          "9" = 9;
          "a" = 10;
          "b" = 11;
          "c" = 12;
          "d" = 13;
          "e" = 14;
          "f" = 15;
        }
        .${c};
    in
    lib.foldl' (acc: c: acc * 16 + digit c) 0 (lib.stringToCharacters (lib.toLower h));

  # "#24273a" -> "36 39 58"
  rgb =
    hex:
    let
      h = lib.removePrefix "#" hex;
      part = o: toString (hexToInt (builtins.substring o 2 h));
    in
    "${part 0} ${part 2} ${part 4}";

  mkZellij =
    t:
    let
      a = mkAnsi t;
      # Every UI component takes base/background plus four emphasis slots. The
      # emphasis ramp is shared so highlights stay consistent across components.
      comp = name: base: background: ''
        ${name} {
            base ${rgb base}
            background ${rgb background}
            emphasis_0 ${rgb t.accent1}
            emphasis_1 ${rgb t.primary}
            emphasis_2 ${rgb t.secondary}
            emphasis_3 ${rgb t.accent3}
        }
      '';
    in
    ''
      // Dynamic tokenized theme — generated from palette tokens.
      // Zellij takes DECIMAL rgb triples, not hex.
      //
      // Two layers, both emitted on purpose:
      //   * base palette (fg/bg/red/…) — indexed-colour fallback inside panes.
      //   * UI components (ribbon/frame/text/…) — the actual chrome: tab bar,
      //     status bar and pane frames. Where both could apply, the components
      //     win, which is what makes the bar follow the palette rather than
      //     zellij's stock green.
      //
      // NOTE: the docs say exit_code_success/_error "only use base". They do
      // not — zellij 0.45 rejects a base-only block and needs the full six
      // keys, same as every other component. Verified against the binary.
      themes {
          dynamic-tokenized-theme {
              fg ${rgb t.fg}
              bg ${rgb t.bg}
              black ${rgb a.black}
              red ${rgb a.red}
              green ${rgb a.green}
              yellow ${rgb a.yellow}
              blue ${rgb a.blue}
              magenta ${rgb a.magenta}
              cyan ${rgb a.cyan}
              white ${rgb a.white}
              orange ${rgb t.accent1}

              ${comp "text_unselected" t.fg t.bg}
              ${comp "text_selected" t.bg t.primary}
              ${comp "ribbon_unselected" t.muted t.surface}
              ${comp "ribbon_selected" t.bg t.primary}
              ${comp "table_title" t.primary t.bg}
              ${comp "table_cell_unselected" t.fg t.bg}
              ${comp "table_cell_selected" t.bg t.primary}
              ${comp "list_unselected" t.fg t.bg}
              ${comp "list_selected" t.bg t.primary}
              ${comp "frame_unselected" t.border t.bg}
              ${comp "frame_selected" t.primary t.bg}
              ${comp "frame_highlight" t.accent1 t.bg}
              ${comp "exit_code_success" t.success t.bg}
              ${comp "exit_code_error" t.error t.bg}
          }
      }
    '';

  # Zed theme (JSON). A fixed theme name ("dynamic-tokenized-theme") whose file is swapped
  # per scheme, so settings.json can pin it once and Zed hot-reloads on change.
  mkZed =
    name: t:
    let
      a = mkAnsi t;
      hl = c: { color = c; };
      appearance = if lib.hasInfix "light" name then "light" else "dark";
    in
    builtins.toJSON {
      "$schema" = "https://zed.dev/schema/themes/v0.2.0.json";
      name = "dynamic-tokenized-theme";
      author = "generated";
      themes = [
        {
          name = "dynamic-tokenized-theme";
          inherit appearance;
          style = {
            "background" = t.bg;
            "border" = t.border;
            "border.variant" = t.borderMuted;
            "text" = t.fg;
            "text.muted" = t.muted;
            "text.accent" = t.primary;
            "element.background" = t.surface;
            "element.hover" = t.surfaceAlt;
            "element.selected" = t.surfaceAlt;
            "surface.background" = t.bgAlt;
            "elevated_surface.background" = t.surface;
            "editor.background" = t.bg;
            "editor.foreground" = t.fg;
            "editor.gutter.background" = t.bg;
            "editor.line_number" = t.muted;
            "editor.active_line_number" = t.fg;
            "editor.active_line.background" = t.bgAlt;
            "status_bar.background" = t.bgAlt;
            "title_bar.background" = t.bgAlt;
            "toolbar.background" = t.bg;
            "tab_bar.background" = t.bgAlt;
            "tab.active_background" = t.bg;
            "tab.inactive_background" = t.bgAlt;
            "panel.background" = t.bgAlt;
            "scrollbar.thumb.background" = t.surfaceAlt;
            "terminal.background" = t.bg;
            "terminal.foreground" = t.fg;
            "terminal.ansi.black" = a.black;
            "terminal.ansi.red" = a.red;
            "terminal.ansi.green" = a.green;
            "terminal.ansi.yellow" = a.yellow;
            "terminal.ansi.blue" = a.blue;
            "terminal.ansi.magenta" = a.magenta;
            "terminal.ansi.cyan" = a.cyan;
            "terminal.ansi.white" = a.white;
            "terminal.ansi.bright_black" = a.brightBlack;
            "terminal.ansi.bright_red" = a.brightRed;
            "terminal.ansi.bright_green" = a.brightGreen;
            "terminal.ansi.bright_yellow" = a.brightYellow;
            "terminal.ansi.bright_blue" = a.brightBlue;
            "terminal.ansi.bright_magenta" = a.brightMagenta;
            "terminal.ansi.bright_cyan" = a.brightCyan;
            "terminal.ansi.bright_white" = a.brightWhite;
            "error" = t.error;
            "warning" = t.warning;
            "success" = t.success;
            "hint" = t.hint;
            "created" = t.success;
            "modified" = t.warning;
            "deleted" = t.error;
            "syntax" = {
              "keyword" = hl t.secondary;
              "function" = hl t.primary;
              "string" = hl t.success;
              "type" = hl t.warning;
              "comment" = hl t.muted;
              "number" = hl t.accent1;
              "constant" = hl t.accent1;
              "boolean" = hl t.accent1;
              "variable" = hl t.fg;
              "property" = hl t.hint;
              "operator" = hl t.accent2;
              "punctuation" = hl t.muted;
              "tag" = hl t.primary;
              "attribute" = hl t.hint;
              "link_uri" = hl t.hint;
              "title" = hl t.primary;
            };
            "players" = [
              {
                cursor = t.primary;
                background = t.primary;
                selection = t.surfaceAlt;
              }
            ];
          };
        }
      ];
    };

  # GTK / libadwaita named-colour overrides (for nemo and other GTK apps).
  # Best-effort: adw-gtk3 / libadwaita honour these @define-color names, but
  # full GTK theming is owned by Stylix at build time.
  mkGtk = t: ''
    /* Dynamic tokenized theme — generated from palette tokens. */
    @define-color window_bg_color ${t.bg};
    @define-color window_fg_color ${t.fg};
    @define-color view_bg_color ${t.bg};
    @define-color view_fg_color ${t.fg};
    @define-color headerbar_bg_color ${t.bgAlt};
    @define-color headerbar_fg_color ${t.fg};
    @define-color card_bg_color ${t.surface};
    @define-color card_fg_color ${t.fg};
    @define-color popover_bg_color ${t.surface};
    @define-color popover_fg_color ${t.fg};
    @define-color dialog_bg_color ${t.surface};
    @define-color dialog_fg_color ${t.fg};
    @define-color sidebar_bg_color ${t.bgAlt};
    @define-color sidebar_fg_color ${t.fg};
    @define-color accent_color ${t.primary};
    @define-color accent_bg_color ${t.primary};
    @define-color accent_fg_color ${t.bg};
    @define-color destructive_color ${t.error};
    @define-color success_color ${t.success};
    @define-color warning_color ${t.warning};
    @define-color error_color ${t.error};
    @define-color theme_bg_color ${t.bg};
    @define-color theme_base_color ${t.bg};
    @define-color theme_fg_color ${t.fg};
    @define-color theme_text_color ${t.fg};
    @define-color theme_selected_bg_color ${t.primary};
    @define-color theme_selected_fg_color ${t.bg};
    @define-color insensitive_bg_color ${t.bgAlt};
    @define-color insensitive_fg_color ${t.muted};
    @define-color borders ${t.border};
  '';

  # wofi menu (GTK CSS). Themes EVERY wofi launcher from the same tokens — the
  # app drun menu (Mod+D), the theme switcher, and the gopass password launcher
  # + store switcher (home/gopass.nix). Self-contained: the palette is inlined
  # as @define-color via mkGtkPalette (no @import), so the stylesheet always
  # parses even as a /nix/store symlink — unlike a relative @import, which GTK
  # can resolve against the store dir and then drop (see notifications.nix).
  # Live-swappable: the live file ~/.config/wofi/style.css is a symlink
  # retargeted by theme-set (./seed.nix), and wofi re-reads it on every launch
  # (spawned fresh, not a daemon), so a switch needs no reload command.
  mkWofi =
    t:
    mkGtkPalette t
    + ''

      window {
        margin: 0px;
        background-color: @bg;
        color: @fg;
        border: 1px solid @border;
        font-family: "RobotoMono Nerd Font", monospace;
        font-size: 13px;
      }

      #input {
        margin: 8px;
        padding: 6px 8px;
        background-color: @surface;
        color: @fg;
        border: 1px solid @border;
        border-radius: 0;
      }
      #input:focus { border-color: @primary; }

      #outer-box { margin: 0px; background-color: @bg; }
      #inner-box { margin: 0px; background-color: @bg; }
      #scroll { margin: 0px 4px 8px 4px; }

      #entry {
        padding: 4px 8px;
        background-color: transparent;
        border: none;
        border-radius: 0;
      }
      #entry:selected { background-color: @primary; }

      #text { color: @fg; margin: 0px 4px; }
      #entry:selected #text { color: @bg; }
      #text:selected { color: @bg; }

      #img { margin-right: 6px; }
    '';

  # Pre-render EVERY palette so a runtime switcher can flip between them without
  # a rebuild. Landed read-only at ~/.config/theme/palettes/<name>/{palette.css,
  # env,sway.colors}; the live files the apps read are symlinks into this tree
  # (seeded below, retargeted by theme-set). This is what makes on-the-fly
  # switching possible — the store still holds one file per (scheme, artefact).
  perScheme = name: rec {
    p = loadPalette name;
    files = {
      "palette.css" = mkGtkPalette p.tokens;
      "wofi.css" = mkWofi p.tokens;
      "env" = mkEnv p.tokens;
      "sway.colors" = mkSwayColors p.tokens;
      "alacritty.toml" = mkAlacritty p.tokens;
      "tmux.conf" = mkTmux p.tokens;
      "zellij.kdl" = mkZellij p.tokens;
      "zed.json" = mkZed name p.tokens;
      "gtk.css" = mkGtk p.tokens;
    };
  };

  paletteStoreFiles = lib.listToAttrs (
    lib.concatMap (
      name:
      map (fname: {
        name = ".config/theme/palettes/${name}/${fname}";
        value.text = (perScheme name).files.${fname};
      }) (builtins.attrNames (perScheme name).files)
    ) available
  );
in
{
  options.dynamic.theme = {
    scheme = lib.mkOption {
      type = lib.types.nullOr lib.types.str;
      default = null;
      description = ''
        Palette name (filename in themes/palettes/ without .nix). When null,
        falls back to the host's ui.theme.scheme (osConfig) and then to
        catppuccin-macchiato. This is the *build-time default*; a runtime
        `theme-switcher` choice (state file) takes precedence at activation.
      '';
    };

    writeWaybarPalette = lib.mkOption {
      type = lib.types.bool;
      default = true;
      description = "Seed ~/.config/waybar/palette.css as a symlink into the active scheme.";
    };

    writeWofiPalette = lib.mkOption {
      type = lib.types.bool;
      default = true;
      description = ''
        Seed ~/.config/wofi/style.css as a symlink into the active scheme, so
        every wofi menu (app launcher, theme switcher, gopass password + store
        selectors) follows the selected palette and live-swaps on theme change.
      '';
    };

    writeSwayncPalette = lib.mkOption {
      type = lib.types.bool;
      default = true;
      description = "Seed ~/.config/swaync/palette.css as a symlink into the active scheme.";
    };

    writeShellEnv = lib.mkOption {
      type = lib.types.bool;
      default = true;
      description = "Seed ~/.config/theme/env as a symlink into the active scheme.";
    };

    writeGtkOverride = lib.mkOption {
      type = lib.types.bool;
      default = true;
      description = ''
        Seed ~/.config/gtk-{3,4}.0/gtk.css with token-based @define-color
        overrides (best-effort GTK/nemo theming). Skipped automatically if those
        paths are already managed by home-manager/Stylix (a /nix/store symlink),
        so it never fights a build-time GTK theme. Set false to disable entirely.
      '';
    };

    tokens = lib.mkOption {
      type = lib.types.attrsOf lib.types.str;
      readOnly = true;
      description = "Resolved semantic tokens from the chosen palette.";
    };

    paletteName = lib.mkOption {
      type = lib.types.str;
      readOnly = true;
      description = "Resolved palette name (the build-time default scheme).";
    };
  };

  config = {
    dynamic.theme = {
      tokens = T;
      paletteName = palette.name;
    };

    # Store-backed catalogue of every scheme + a static listing for the menu.
    home.file = paletteStoreFiles // {
      ".config/theme/available-schemes".text = lib.concatStringsSep "\n" available + "\n";
    };

    # Seed the *live* palette symlinks from the remembered scheme: the runtime
    # state file if present (a theme-switcher choice), else the build default.
    # Re-running on every activation keeps a rebuild from clobbering a live
    # choice, exactly like gopass' current-store handling.
    home.activation.themeSeed = lib.hm.dag.entryAfter [ "writeBoundary" ] ''
      state_dir="$HOME/.local/state/theme"
      state_file="$state_dir/current-scheme"
      default=${lib.escapeShellArg chosenName}
      available=${lib.escapeShellArg (lib.concatStringsSep " " available)}

      mkdir -p "$state_dir"
      [ -f "$state_file" ] || printf '%s\n' "$default" > "$state_file"
      scheme="$(cat "$state_file")"
      case " $available " in
        *" $scheme "*) : ;;
        *) scheme="$default" ;;
      esac

      pal="$HOME/.config/theme/palettes/$scheme"
      ${import ./seed.nix { inherit lib cfg; }}
      printf '%s\n' "$scheme" > "$HOME/.config/theme/active-scheme"
    '';
  };
}
