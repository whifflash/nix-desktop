{
  config,
  lib,
  pkgs,
  osConfig ? { },
  ...
}:
let
  cfg = config.dynamic.desktop;
  niriOn = lib.attrByPath [ "programs" "niri" "enable" ] false osConfig;

  term = lib.getExe cfg.terminal;

  # Where niri saves screenshots. niri only creates the LAST folder of
  # screenshot-path, so if ~/Pictures is missing the on-disk save fails
  # silently and only the clipboard copy survives — which looks like "Space
  # only copies". The activation step below pre-creates it. One binding drives
  # both the KDL path and the mkdir so they can never drift.
  screenshotDir = "${config.home.homeDirectory}/Pictures/Screenshots";

  # Focus-ring colours from the resolved palette tokens (home/themes/tokens.nix),
  # the same source Sway's window colours use — no second palette lookup, no
  # drift. `primary` mirrors Sway's focused border. Resolves at build time:
  # unlike Sway/Waybar (live-swapped by theme-set) niri's ring updates on the
  # next rebuild, since niri's single-file KDL has no include for the switcher.
  t = config.dynamic.theme.tokens;
  focusActive = t.primary;
  focusInactive = t.borderMuted;

  # Desktop wallpaper. niri has no built-in background, so — like Sway (which
  # sets it with `output * bg`) — run swaybg with the same image + mode
  # (dynamic.wallpaper, fed from ui.theme). Emits nothing when disabled.
  wp = config.dynamic.wallpaper;
  wallpaperSpawn =
    lib.optionalString (wp.enable && wp.dir != null)
      ''spawn-at-startup "${pkgs.swaybg}/bin/swaybg" "-i" "${toString wp.dir}/${wp.file}" "-m" "${wp.mode}"'';

  # Named workspaces, in order. Super+N focuses the Nth and Super+Shift+N moves
  # the focused column there; apps are pinned to them by app-id in the
  # window-rules block below, so they always land on their workspace whenever
  # opened. Names are the Super+N number so the bar label always matches the
  # shortcut (niri's own spatial index can drift after a live config reload).
  workspaces = cfg.niri.workspaces;
  wsDecls = lib.concatStringsSep "\n    " (map (n: ''workspace "${n}"'') workspaces);
  wsFocus = lib.concatStringsSep "\n" (
    lib.imap1 (i: n: ''Mod+${toString i} { focus-workspace "${n}"; }'') workspaces
  );
  wsMove = lib.concatStringsSep "\n" (
    lib.imap1 (i: n: ''Mod+Shift+${toString i} { move-column-to-workspace "${n}"; }'') workspaces
  );

  xkbVariant = lib.optionalString (cfg.keyboard.variant != "") ''variant "${cfg.keyboard.variant}"'';
  xkbOptions = lib.optionalString (cfg.keyboard.options != "") ''options "${cfg.keyboard.options}"'';
  touchpadTap = lib.optionalString cfg.touchpad.tap "tap";

  # Drop-down ("quake") terminal for niri, bound to Mod+i. niri has no native
  # scratchpad and its workspaces are a dynamic spatial stack (a stash workspace
  # can't be hidden — it would steal Mod+1 and clutter j/k navigation), so this is
  # *ephemeral*: hiding CLOSES the window and showing re-spawns it. All state
  # lives in whatever dynamic.desktop.scratchpad.command runs (a persistent tmux
  # session by default), so nothing is lost — closing the terminal only detaches
  # the client. Net effect: zero workspace-stack impact.
  dropdownAppId = cfg.scratchpad.appId;
  dropdownTerm = pkgs.writeShellScript "niri-dropdown-term" ''
    set -euo pipefail
    app_id="${dropdownAppId}"

    windows=$(niri msg -j windows)
    win=$(printf '%s' "$windows" | ${pkgs.jq}/bin/jq -c --arg a "$app_id" 'map(select(.app_id == $a)) | .[0] // empty')

    # Not running → launch it. The window-rule floats + sizes it on the current
    # workspace, focused.
    if [ -z "$win" ]; then
      exec ${term} --class "$app_id" -e ${cfg.scratchpad.command}
    fi

    id=$(printf '%s' "$win" | ${pkgs.jq}/bin/jq -r '.id')
    win_ws=$(printf '%s' "$win" | ${pkgs.jq}/bin/jq -r '.workspace_id')
    win_focused=$(printf '%s' "$win" | ${pkgs.jq}/bin/jq -r '.is_focused')

    cur=$(niri msg -j workspaces | ${pkgs.jq}/bin/jq -c 'map(select(.is_focused)) | .[0] // empty')
    cur_ws=$(printf '%s' "$cur" | ${pkgs.jq}/bin/jq -r '.id')

    if [ "$win_ws" = "$cur_ws" ]; then
      # On the current workspace: if focused, hide it by CLOSING the window (the
      # scratch session persists server-side); otherwise just raise it.
      if [ "$win_focused" = "true" ]; then
        niri msg action close-window --id "$id"
      else
        niri msg action focus-window --id "$id"
      fi
    else
      # Stashed or on another workspace → summon it here and focus it. Reference
      # the current workspace by name; if unnamed, name it just for the move, then
      # remove the name (avoids fragile per-output workspace indices).
      cur_name=$(printf '%s' "$cur" | ${pkgs.jq}/bin/jq -r '.name // empty')
      if [ -n "$cur_name" ]; then
        niri msg action move-window-to-workspace "$cur_name" --window-id "$id" --focus false
      else
        tmp="__dropdown_summon__"
        niri msg action set-workspace-name "$tmp"
        niri msg action move-window-to-workspace "$tmp" --window-id "$id" --focus false
        niri msg action unset-workspace-name "$tmp"
      fi
      niri msg action focus-window --id "$id"
    fi
  '';

  niriConfig = ''
    // niri config — managed by home-manager (home/desktop/niri.nix).
    // Reference: https://github.com/YaLTeR/niri/wiki/Configuration
    // niri hot-reloads this file on save. Validate on the target machine with:
    //   niri validate

    input {
        keyboard {
            xkb {
                // Layout/variant/options come from dynamic.desktop.keyboard —
                // the same values Sway uses, so both sessions type the same.
                layout "${cfg.keyboard.layout}"
                ${xkbVariant}
                ${xkbOptions}
            }
        }
        touchpad {
            ${touchpadTap}
            natural-scroll
            middle-emulation
            accel-speed 0.4
            accel-profile "adaptive"
        }
    }

    prefer-no-csd

    // Screenshots. In the built-in screenshot UI (Print) Space/Enter save to
    // disk AND copy to the clipboard; Ctrl+C is clipboard-only. Those UI keys
    // are hardcoded by niri (not configurable). niri only mkdirs the LAST
    // folder of this path, so the dir is pre-created by this module's
    // activation step (see screenshotDir) — otherwise the save fails silently.
    screenshot-path "${screenshotDir}/Screenshot from %Y-%m-%d %H-%M-%S.png"

    // niri has no built-in Xwayland; xwayland-satellite (installed by the niri
    // system module, spawned below) provides X11 support. DISPLAY is exported so
    // X clients find the satellite.
    environment {
        DISPLAY ":0"
        NIXOS_OZONE_WL "1"
    }

    // Monitor layout (dynamic.desktop.niri.outputs — machine-specific, fed by the
    // consumer). Names come from `niri msg outputs`; disconnected outputs are
    // simply ignored, so this also covers the laptop-only (undocked) case.
    ${cfg.niri.outputs}

    // Persistent named workspaces. Apps pin here via the window-rules below;
    // Super+N focus them, Super+Shift+N send a column.
    ${wsDecls}

    spawn-at-startup "${pkgs.waybar}/bin/waybar"
    spawn-at-startup "${pkgs.xwayland-satellite}/bin/xwayland-satellite"

    // Desktop wallpaper via swaybg — same image + mode Sway uses. Present only
    // when dynamic.wallpaper is enabled.
    ${wallpaperSpawn}

    layout {
        gaps 8
        center-focused-column "never"
        preset-column-widths {
            proportion 0.33333
            proportion 0.5
            proportion 0.66667
        }
        default-column-width { proportion 0.5; }
        focus-ring {
            width 2
            active-color "${focusActive}"
            inactive-color "${focusInactive}"
        }
        border {
            off
        }
    }

    // Drop-down terminal (Mod+i): floating, ~70%×60%, anchored to the top of the
    // screen (quake style). Matched by the app-id the terminal is launched with in
    // the toggle script (dropdownTerm). Only this window is floated.
    window-rule {
        match app-id="^${dropdownAppId}$"
        open-floating true
        default-column-width { proportion 0.7; }
        default-window-height { proportion 0.6; }
        default-floating-position x=0 y=0 relative-to="top"
    }

    // ── App → workspace pinning ────────────────────────────────────────────
    // Whenever one of these apps opens it lands on its named workspace, however
    // it was launched. app-id is a case-insensitive regex; if one doesn't match,
    // check the real id with:  niri msg -j windows | jq -r '.[].app_id'
    window-rule {
        match app-id="(?i)(alacritty|foot|kitty|wezterm|ghostty)"
        exclude app-id="${dropdownAppId}"
        open-on-workspace "1"
    }
    window-rule {
        match app-id="(?i)zed"
        open-on-workspace "2"
    }
    window-rule {
        match app-id="(?i)(firefox|chromium|chrome)"
        open-on-workspace "3"
    }
    window-rule {
        match app-id="(?i)(nemo|nautilus|thunar|pcmanfm|dolphin)"
        open-on-workspace "4"
    }
    window-rule {
        match app-id="(?i)element"
        open-on-workspace "6"
    }
    window-rule {
        match app-id="(?i)(evolution|thunderbird)"
        open-on-workspace "7"
    }

    binds {
        Mod+Return hotkey-overlay-title="Terminal" { spawn "${term}"; }
        Mod+D hotkey-overlay-title="App launcher" { spawn "${pkgs.wofi}/bin/wofi" "--show" "drun"; }
        Mod+P hotkey-overlay-title="Password launcher" { spawn "sh" "-lc" "gopass-launcher"; }
        Mod+Shift+P hotkey-overlay-title="Password store switcher" { spawn "sh" "-lc" "gopass-switcher"; }
        Mod+Shift+T hotkey-overlay-title="Theme switcher" { spawn "sh" "-lc" "theme-switcher"; }
        Mod+I hotkey-overlay-title="Drop-down terminal" { spawn "${dropdownTerm}"; }

        Mod+Q { close-window; }
        Mod+Shift+X hotkey-overlay-title="Lock screen" { spawn "${pkgs.swaylock-effects}/bin/swaylock" "-f"; }
        Mod+Shift+E { quit; }
        Mod+Escape hotkey-overlay-title="Show hotkeys" { show-hotkey-overlay; }
        // Restart Waybar. Uses the shared reload_waybar.sh (deployed by
        // ./waybar.nix) so the "kill the wrapGAppsHook-wrapped process, keep a
        // single instance" logic lives in one place, matching Sway.
        Mod+Shift+R hotkey-overlay-title="Restart Waybar" { spawn "${config.home.homeDirectory}/.config/waybar/reload_waybar.sh"; }

        Mod+H { focus-column-left; }
        Mod+L { focus-column-right; }
        // j/k move down/up vim-style: between stacked windows in a column, then
        // across workspaces. With one window per column (the usual case) this is
        // simply "focus the workspace below/above".
        Mod+J { focus-window-or-workspace-down; }
        Mod+K { focus-window-or-workspace-up; }
        // Mod+Shift moves the focused COLUMN: left/right within the workspace,
        // down/up to the adjacent workspace — consistent with Mod+Shift+N below.
        Mod+Shift+H { move-column-left; }
        Mod+Shift+L { move-column-right; }
        Mod+Shift+J { move-column-to-workspace-down; }
        Mod+Shift+K { move-column-to-workspace-up; }
        // Toggle between the current and previously-focused workspace — the
        // equivalent of Sway's `workspace back_and_forth`.
        Mod+Space { focus-workspace-previous; }

        // Multi-monitor: Ctrl focuses another output, Ctrl+Shift moves the whole
        // focused WORKSPACE there (it then sticks to that monitor). H/L assume
        // monitors side by side; swap the suffix for -up/-down (stacked) or
        // -next/-previous (layout-agnostic).
        Mod+Ctrl+H hotkey-overlay-title="Focus monitor left" { focus-monitor-left; }
        Mod+Ctrl+L hotkey-overlay-title="Focus monitor right" { focus-monitor-right; }
        Mod+Ctrl+J hotkey-overlay-title="Focus monitor below" { focus-monitor-down; }
        Mod+Ctrl+K hotkey-overlay-title="Focus monitor above" { focus-monitor-up; }
        Mod+Ctrl+Shift+H hotkey-overlay-title="Move workspace to left monitor" { move-workspace-to-monitor-left; }
        Mod+Ctrl+Shift+L hotkey-overlay-title="Move workspace to right monitor" { move-workspace-to-monitor-right; }
        Mod+Ctrl+Shift+J hotkey-overlay-title="Move workspace to monitor below" { move-workspace-to-monitor-down; }
        Mod+Ctrl+Shift+K hotkey-overlay-title="Move workspace to monitor above" { move-workspace-to-monitor-up; }

        Mod+F { maximize-column; }
        Mod+Shift+F { fullscreen-window; }
        Mod+R { switch-preset-column-width; }
        Mod+Minus { set-column-width "-10%"; }
        Mod+Equal { set-column-width "+10%"; }

    ${wsFocus}
    ${wsMove}

        Print { screenshot; }
        Mod+Print { screenshot-window; }
        // Whole focused screen straight to disk (+clipboard), no selection UI.
        Mod+Shift+S hotkey-overlay-title="Screenshot screen to file" { screenshot-screen; }

        XF86AudioRaiseVolume hotkey-overlay-title="Volume up" allow-when-locked=true { spawn "${pkgs.wireplumber}/bin/wpctl" "set-volume" "-l" "1.0" "@DEFAULT_AUDIO_SINK@" "5%+"; }
        XF86AudioLowerVolume hotkey-overlay-title="Volume down" allow-when-locked=true { spawn "${pkgs.wireplumber}/bin/wpctl" "set-volume" "@DEFAULT_AUDIO_SINK@" "5%-"; }
        XF86AudioMute hotkey-overlay-title="Mute audio" allow-when-locked=true { spawn "${pkgs.wireplumber}/bin/wpctl" "set-mute" "@DEFAULT_AUDIO_SINK@" "toggle"; }
        XF86AudioMicMute hotkey-overlay-title="Mute microphone" allow-when-locked=true { spawn "${pkgs.wireplumber}/bin/wpctl" "set-mute" "@DEFAULT_AUDIO_SOURCE@" "toggle"; }
        XF86MonBrightnessUp hotkey-overlay-title="Brightness up" allow-when-locked=true { spawn "${pkgs.brightnessctl}/bin/brightnessctl" "set" "5%+"; }
        XF86MonBrightnessDown hotkey-overlay-title="Brightness down" allow-when-locked=true { spawn "${pkgs.brightnessctl}/bin/brightnessctl" "set" "5%-"; }
    }
  '';
in
{
  # niri home configuration. Applies only when the HOST enables niri
  # (programs.niri.enable); imported unconditionally like ./sway.nix.
  config = lib.mkIf (cfg.enable && niriOn) {
    # Shared Wayland home base (tray, polkit agent, keyring, common apps).
    wayland.common.enable = true;

    # alacritty / nemo / networkmanagerapplet come from ./wayland-common.nix.
    home.packages = with pkgs; [
      brightnessctl
      gsimplecal
    ];

    # Pre-create the screenshot folder: niri only mkdirs the LAST path
    # component, so a missing ~/Pictures would silently drop the on-disk copy.
    home.activation.niriScreenshotDir = lib.hm.dag.entryAfter [ "writeBoundary" ] ''
      mkdir -p ${lib.escapeShellArg screenshotDir}
    '';

    xdg.configFile."niri/config.kdl".text = niriConfig;
  };
}
