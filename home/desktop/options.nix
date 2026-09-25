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
        default = "${lib.getExe pkgs.zellij} attach --create --force-run-commands scratch";
        defaultText = lib.literalExpression ''"''${lib.getExe pkgs.zellij} attach --create --force-run-commands scratch"'';
        description = ''
          Command run inside the drop-down terminal (Mod+i / Mod+Shift+Return).
          Attaches the persistent zellij "scratch" session, creating it from the
          declared layout (home/apps/zellij.nix) if it does not exist. Zellij
          resurrects a serialized session natively on attach, so this needs none
          of the restore-before-attach machinery tmux required;
          `--force-run-commands` skips zellij's "Press ENTER to run…" prompt.
          A config.toml [desktop].scratchpadCommand overrides this.
        '';
      };
      title = mkOption {
        type = types.str;
        default = "TMuxScratchpad";
        description = "Window title Sway matches to treat the drop-down as its scratchpad.";
      };
      key = mkOption {
        type = types.str;
        default = "i";
        example = "o";
        description = ''
          Single key combined with the modifier to toggle the drop-down
          (Mod+<key>). Uppercased for niri, lowercased for Sway, where an
          uppercase letter would mean Shift.
        '';
      };
      appId = mkOption {
        type = types.str;
        default = "dropdown-term";
        description = "app-id niri matches to float and place the drop-down window.";
      };
      workspace = mkOption {
        type = types.str;
        default = "scratch";
        description = ''
          niri workspace the drop-down terminal permanently lives on. The toggle
          focuses this workspace and returns with focus-workspace-previous; the
          window itself never moves, which is what keeps it from disturbing the
          focus of whatever workspace you were on.

          Named workspaces always exist, so this one appears in workspace
          navigation. Declare it FIRST (niri.nix does) so the numbered
          workspaces keep name == index and numeric references stay unambiguous.

          Unused under Sway, which has a real scratchpad.
        '';
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
          "2"
          "3"
          "4"
          "5"
          "6"
          "7"
        ];
        description = ''
          Named, persistent niri workspaces in order. The drop-down's stash
          workspace occupies position 1, so these start at "2" and the Nth entry
          is bound to Mod+(N+1) -- workspace "2" is Mod+2. Keeping each name
          equal to its index also makes niri's numeric workspace references
          unambiguous: niri parses a numeric reference as an INDEX, not a name.
          The app->workspace pinning rules reference "2"-"7".
        '';
      };
    };
  };
}
