{
  lib,
  pkgs,
  osConfig ? { },
  ...
}:
let
  inherit (lib) mkOption types;
  wmOn = wm: lib.attrByPath [ "programs" wm "enable" ] false osConfig;
in
{
  # Consumer contract for the shared Wayland desktop shell. Every value here is
  # either fed from the host (config.toml via the hostcfg feed) or left at its
  # default. The shell modules (sway/niri/waybar/kanshi/…) read ONLY these
  # options and `osConfig.ui.*` — never a repo-specific config source — so the
  # same files serve every consumer of this layer.
  options.dynamic.desktop = {
    enable = mkOption {
      type = types.bool;
      default = wmOn "sway" || wmOn "niri";
      defaultText = lib.literalExpression "osConfig.programs.sway.enable || osConfig.programs.niri.enable";
      description = ''
        Deploy the shared desktop shell (waybar, swaync, swaylock, kanshi,
        flameshot). Defaults to on whenever the host enables Sway or niri, so
        the module can be imported unconditionally.
      '';
    };

    terminal = mkOption {
      type = types.package;
      default = pkgs.alacritty;
      defaultText = lib.literalExpression "pkgs.alacritty";
      description = "Terminal launched by Mod+Return and used for the drop-down scratchpad (needs meta.mainProgram).";
    };

    keyboard = {
      layout = mkOption {
        type = types.str;
        default = "us";
        description = "XKB layout (Sway xkb_layout / niri xkb.layout).";
      };
      variant = mkOption {
        type = types.str;
        default = "";
        description = "XKB variant; empty = none.";
      };
      options = mkOption {
        type = types.str;
        default = "";
        example = "caps:super,terminate:ctrl_alt_bksp";
        description = "Comma-separated XKB options; empty = none.";
      };
    };

    touchpad.tap = mkOption {
      type = types.bool;
      default = true;
      description = "Tap-to-click on touchpads.";
    };

    scratchpad = {
      command = mkOption {
        type = types.str;
        default = "${lib.getExe pkgs.tmux} new-session -A -s scratch";
        defaultText = lib.literalExpression ''"''${lib.getExe pkgs.tmux} new-session -A -s scratch"'';
        description = ''
          Command run inside the drop-down terminal (Mod+i / Mod+Shift+Return).
          The tmux module (home/apps/tmux.nix) sets this to its `tmux-scratch`
          launcher, which on a cold tmux server restores the last resurrect save
          synchronously BEFORE attaching to the persistent "scratch" session, so
          the drop-down survives reboots without racing a live client. The plain
          attach here is only the fallback if that module is not loaded. A
          config.toml [desktop].scratchpadCommand overrides both.
        '';
      };
      title = mkOption {
        type = types.str;
        default = "TMuxScratchpad";
        description = "Window title Sway matches to treat the drop-down as its scratchpad.";
      };
      appId = mkOption {
        type = types.str;
        default = "dropdown-term";
        description = "app-id niri matches to float and place the drop-down window.";
      };
    };

    waybar = {
      vpn = {
        wg = mkOption {
          type = types.nullOr types.str;
          default = null;
          example = "office-wg";
          description = "NetworkManager connection name of a WireGuard tunnel shown as a Waybar toggle; null omits the module.";
        };
        ovpn = mkOption {
          type = types.nullOr types.str;
          default = null;
          example = "office-ovpn";
          description = "NetworkManager connection name of an OpenVPN tunnel shown as a Waybar toggle; null omits the module.";
        };
      };
      displayProfiles = {
        docked = mkOption {
          type = types.nullOr types.str;
          default = null;
          example = "docked";
          description = "kanshi profile behind the Waybar \"docked\" button; null omits both display buttons. Requires kanshi.config.";
        };
        laptop = mkOption {
          type = types.nullOr types.str;
          default = null;
          example = "laptop";
          description = "kanshi profile behind the Waybar \"laptop\" button.";
        };
      };
    };

    kanshi.config = mkOption {
      type = types.nullOr types.path;
      default = null;
      description = "kanshi profiles file (machine-specific: keyed on monitor serials, so it lives in the consumer). null disables kanshi.";
    };

    niri = {
      outputs = mkOption {
        type = types.lines;
        default = "";
        description = "Raw KDL `output { … }` blocks spliced into niri's config (machine-specific monitor names/modes/positions; lives in the consumer).";
      };
      workspaces = mkOption {
        type = types.listOf types.str;
        default = [
          "1"
          "2"
          "3"
          "4"
          "5"
          "6"
          "7"
        ];
        description = "Named, persistent niri workspaces in order; Mod+N focuses the Nth. The app→workspace pinning rules reference \"1\"–\"7\".";
      };
    };
  };
}
