{
  config,
  lib,
  pkgs,
  ...
}:
let
  cfg = config.dynamic.zellij;

  # The Wayland clipboard helper is Linux-only (wl-clipboard has darwin in
  # meta.badPlatforms). Used at VALUE level only, never to shape attribute
  # names — same rule as home/apps/gopass.nix.
  isLinux = pkgs.stdenv.hostPlatform.isLinux;

  # Render one declared tab. Names are DECLARED here rather than captured from a
  # live session, which is the whole point of the migration: a declared name
  # cannot drift or go missing the way tmux-resurrect's captured ones did.
  mkTab =
    tab:
    let
      cwd = lib.optionalString (tab.cwd != "") ''cwd="${tab.cwd}"'';
      cmd = lib.optionalString (tab.command != "") ''command="${tab.command}"'';
    in
    ''
      tab name="${tab.name}"${cwd} {
          pane${cmd}
      }
    '';

  # Ctrl-<letter> sends the control byte of that letter: Ctrl-a = 1 (SOH),
  # Ctrl-b = 2 (STX). Used for the prefix passthrough below, so pressing the
  # prefix twice types a literal one — tmux's `send-prefix`.
  ctrlBytes = lib.listToAttrs (
    lib.imap1 (i: ch: lib.nameValuePair ch i) (lib.stringToCharacters "abcdefghijklmnopqrstuvwxyz")
  );
  prefixLetter = lib.toLower (lib.last (lib.splitString " " cfg.tmuxMode.prefix));
  prefixByte = ctrlBytes.${prefixLetter} or 1;

  # Each Ctrl key zellij's modal defaults claim, and the mode whose
  # `shared_except` block binds it — needed to unbind it in the right place.
  shellKeyModes = {
    "Ctrl p" = "pane";
    "Ctrl n" = "resize";
    "Ctrl s" = "scroll";
    "Ctrl o" = "session";
    "Ctrl t" = "tab";
    "Ctrl h" = "move";
  };
  freeKeysKdl = lib.concatMapStrings (k: ''
    shared_except "${shellKeyModes.${k}}" "locked" { unbind "${k}"; }
  '') cfg.freeShellKeys;

  # Keybinds must go in extraConfig as raw KDL: home-manager's `settings` runs
  # through toKDL, which cannot express bind blocks (nix-community/home-manager#4659).
  # `keybinds` MERGES with zellij's defaults unless clear-defaults=true, so this
  # only adds/overrides what we care about and leaves the rest intact.
  keybindsKdl = ''
    keybinds {
        // Zellij ships a built-in `tmux` mode — a prefix-style island in an
        // otherwise modal keymap. Default trigger is Ctrl-b; retarget it at the
        // prefix so the muscle memory carries over.
        shared_except "tmux" "locked" {
            bind "${cfg.tmuxMode.prefix}" { SwitchToMode "Tmux"; }
        }
        tmux {
            // Prefix twice = send a literal prefix through (tmux send-prefix).
            bind "${cfg.tmuxMode.prefix}" { Write ${toString prefixByte}; SwitchToMode "Normal"; }
            // Splits matching the old tmux config: | horizontal, - vertical.
            // (zellij's tmux mode ships " and % for these; both now work.)
            bind "|" { NewPane "Right"; SwitchToMode "Normal"; }
            bind "-" { NewPane "Down"; SwitchToMode "Normal"; }
            // Resize, which zellij's tmux mode omits entirely. Stays in Tmux
            // mode so repeats work like tmux's `bind -r`.
            // `,` renames the TAB (zellij's default, = tmux rename-window).
            // Panes have no tmux equivalent, so `r` renames the focused pane.
            bind "r" { SwitchToMode "RenamePane"; }
            bind "H" { Resize "Increase Left"; }
            bind "J" { Resize "Increase Down"; }
            bind "K" { Resize "Increase Up"; }
            bind "L" { Resize "Increase Right"; }
        }
    ${lib.optionalString (cfg.freeShellKeys != [ ]) ''

        // Give the shell back the Ctrl keys zellij's modal defaults claim.
        // Ctrl-p/Ctrl-n are history, Ctrl-s forward-search, Ctrl-t fzf's file
        // widget, Ctrl-o operate-and-get-next, and Ctrl-h is Backspace on many
        // terminals. With the prefix above they are redundant anyway.
      ${freeKeysKdl}''}
    }
  '';

  # default_tab_template applies to EVERY tab, so each one gets the bars. The
  # `children` node marks where the tab's own panes are spliced in. Plugin names
  # match `zellij setup --dump-layout default`.
  tabTemplate =
    if cfg.bar == "none" then
      ""
    else if cfg.bar == "compact" then
      ''
        default_tab_template {
            children
            pane size=1 borderless=true {
                plugin location="compact-bar"
            }
        }
      ''
    else
      ''
        default_tab_template {
            pane size=1 borderless=true {
                plugin location="tab-bar"
            }
            children
            pane size=1 borderless=true {
                plugin location="status-bar"
            }
        }
      '';

  # An empty tab list still needs a valid layout, else zellij refuses to start.
  # A bare `tab` picks up the template above and gets a default pane.
  layoutKdl = ''
    layout {
    ${tabTemplate}${if cfg.tabs == [ ] then "    tab
" else lib.concatMapStrings mkTab cfg.tabs}}
  '';
in
{
  options.dynamic.zellij = {
    enable = lib.mkEnableOption "Zellij multiplexer with a declared drop-down session" // {
      default = true;
    };

    sessionName = lib.mkOption {
      type = lib.types.str;
      default = "scratch";
      description = ''
        Session the drop-down attaches to. `zellij attach --create` resurrects it
        if it exists (even after a reboot) and creates it from the declared
        layout otherwise.
      '';
    };

    tabs = lib.mkOption {
      type = lib.types.listOf (
        lib.types.submodule {
          options = {
            name = lib.mkOption {
              type = lib.types.str;
              description = "Tab name. Declared, so it can never go missing on restore.";
            };
            cwd = lib.mkOption {
              type = lib.types.str;
              default = "";
              description = "Working directory for the tab. Empty = zellij's default.";
            };
            command = lib.mkOption {
              type = lib.types.str;
              default = "";
              description = ''
                Command to run in the tab's pane. Empty = a plain shell. Note a
                command pane exits with the command; plain shells are the norm.
              '';
            };
          };
        }
      );
      default = [ ];
      description = ''
        The STABLE set of tabs, declared rather than captured — fed from
        config.toml's [zellij] section via home/hostcfg-feed.nix. Ad-hoc tabs you
        create by hand are not listed here but still come back, because
        `session_serialization` persists the live session on top of this layout.
      '';
    };

    defaultShell = lib.mkOption {
      type = lib.types.str;
      default = "";
      description = ''
        Shell for new panes. Empty leaves zellij's default ($SHELL). Set this to
        pin a specific shell (the previous tmux module pinned zsh).
      '';
    };

    tmuxMode = {
      enable = lib.mkOption {
        type = lib.types.bool;
        default = true;
        description = ''
          Retarget zellij's built-in `tmux` mode at `prefix` and extend it with
          the splits/resize bindings its default set omits. This is not fighting
          zellij: the tmux mode ships with it, we only move the trigger key.
        '';
      };
      prefix = lib.mkOption {
        type = lib.types.str;
        default = "Ctrl a";
        example = "Ctrl b";
        description = ''
          Prefix that enters tmux mode. Must be `Ctrl <letter>`; the letter also
          determines the control byte sent when the prefix is pressed twice.
        '';
      };
    };

    freeShellKeys = lib.mkOption {
      type = lib.types.listOf (lib.types.enum (lib.attrNames shellKeyModes));
      default = lib.attrNames shellKeyModes;
      example = [
        "Ctrl p"
        "Ctrl n"
      ];
      description = ''
        Ctrl keys to take back from zellij's modal defaults, which otherwise
        shadow the shell: Ctrl-p/Ctrl-n history, Ctrl-s forward-search, Ctrl-t
        fzf's file widget, Ctrl-o operate-and-get-next, Ctrl-h Backspace on many
        terminals. All are redundant once the tmux prefix is bound.

        Per-key so you can keep one: drop "Ctrl t" from this list to hand it back
        to zellij's tab mode instead of fzf, for instance. [ ] keeps zellij's
        defaults entirely.
      '';
    };

    bar = lib.mkOption {
      type = lib.types.enum [
        "default"
        "compact"
        "none"
      ];
      default = "default";
      description = ''
        Which status UI each tab gets. "default" is zellij's own: a tab-bar
        across the top (tab names) and a status-bar along the bottom (mode +
        key hints). "compact" is the single-line compact-bar instead. "none"
        drops both.

        This has to be stated explicitly: supplying ANY custom layout replaces
        zellij's built-in one, and the bars live in that layout as plugin panes
        — so a layout without them silently comes up with no tab names and no
        overview at all.
      '';
    };

    scrollbackLines = lib.mkOption {
      type = lib.types.int;
      default = 10000;
      description = ''
        Scrollback lines serialized with each pane. 0 = the full scrollback.
        Requires serialize_pane_viewport, which this module enables.
      '';
    };
  };

  config = lib.mkIf cfg.enable {
    programs.zellij = {
      enable = true;

      # Shell integration is deliberately OFF. It auto-attaches zellij from every
      # interactive shell, which would nest a session inside the drop-down's.
      enableBashIntegration = false;
      enableZshIntegration = false;
      enableFishIntegration = false;

      settings = {
        # Fixed theme name; ./themes/seed.nix swaps the file it resolves to, so
        # the runtime theme-switcher works without rewriting config.kdl.
        theme = "dynamic-tokenized-theme";

        # Created from the declared layout when the session does not exist yet.
        default_layout = cfg.sessionName;

        # THE POINT OF THE MIGRATION. session_serialization is on by default and
        # persists "tabs/panes, cwds and running commands" to the cache dir, so a
        # session survives a reboot and is resurrected on the next attach — no
        # capture/replay of raw escape sequences, which is what made
        # tmux-resurrect fragile (it saved with `capture-pane -epJ` and replayed
        # by `cat`-ing the file back, garbling panes).
        session_serialization = true;

        # Scrollback. NOTE the option name: the zellij WEBSITE calls this
        # `pane_viewport_serialization`, which is WRONG and silently does
        # nothing. The binary's own `zellij setup --dump-config` says
        # `serialize_pane_viewport`. Verified against zellij 0.45.1.
        serialize_pane_viewport = true;
        scrollback_lines_to_serialize = cfg.scrollbackLines;

        # theme_dark/theme_light are intentionally NOT set. They switch "when the
        # host terminal reports a dark or light color palette" — i.e. they QUERY
        # the terminal. Terminal colour queries nested in a multiplexer are
        # exactly what produced the stray `rgb:…` fragments from herdr, so we pin
        # a single theme instead.
      }
      // lib.optionalAttrs (cfg.defaultShell != "") { default_shell = cfg.defaultShell; }
      # Wayland clipboard. zellij ships x11/osx alternatives; on darwin we leave
      # its own default in place rather than pointing at a Linux-only binary.
      // lib.optionalAttrs isLinux { copy_command = "wl-copy"; };

      extraConfig = lib.optionalString cfg.tmuxMode.enable keybindsKdl;

      # Written to ~/.config/zellij/layouts/<sessionName>.kdl.
      layouts.${cfg.sessionName} = layoutKdl;
    };

    home.packages = lib.optionals isLinux [ pkgs.wl-clipboard ]; # copy_command above
  };
}
