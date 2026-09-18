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

  # An empty tab list still needs a valid layout, else zellij refuses to start.
  layoutKdl =
    if cfg.tabs == [ ] then
      ''
        layout {
            pane
        }
      ''
    else
      ''
        layout {
        ${lib.concatMapStrings mkTab cfg.tabs}}
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

      # Written to ~/.config/zellij/layouts/<sessionName>.kdl.
      layouts.${cfg.sessionName} = layoutKdl;
    };

    home.packages = lib.optionals isLinux [ pkgs.wl-clipboard ]; # copy_command above
  };
}
