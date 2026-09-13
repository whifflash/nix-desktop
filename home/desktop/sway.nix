{
  config,
  lib,
  pkgs,
  osConfig ? { },
  ...
}:
let
  cfg = config.dynamic.desktop;
  swayOn = lib.attrByPath [ "programs" "sway" "enable" ] false osConfig;

  mod = "Mod4";
  term = lib.getExe cfg.terminal;
  scratchTitle = cfg.scratchpad.title;
in
{
  # Sway home configuration. Applies only when the HOST enables Sway
  # (programs.sway.enable) — the file is imported unconditionally, so a consumer
  # never needs an import ladder to switch WMs.
  config = lib.mkIf (cfg.enable && swayOn) {
    # Shared Wayland home base (tray, polkit agent, keyring, common apps).
    wayland.common.enable = true;

    # alacritty / nemo / networkmanagerapplet come from ./wayland-common.nix.
    home.packages = with pkgs; [
      nerd-fonts.roboto-mono
      font-awesome
    ];

    # Drop-down ("quake") terminal: spawn-if-missing, then toggle via the
    # scratchpad. What runs inside is dynamic.desktop.scratchpad.command (tmux
    # "scratch" session by default, so hiding never loses state).
    home.file.".config/sway/scripts/toggle_scratchpad.sh" = {
      text = ''
        #!/usr/bin/env bash
        set -euo pipefail
        term='${term}'
        title='${scratchTitle}'

        if ! pgrep -f "$term.*$title" >/dev/null; then
          "$term" --title "$title" -e ${cfg.scratchpad.command} &
          sleep 0.3
        fi

        swaymsg '[title="'"$title"'"] scratchpad show, sticky enable, move position 0 0, resize set 100 ppt 100 ppt, border none'
      '';
      executable = true;
    };

    wayland.windowManager.sway = {
      enable = true;
      package = pkgs.sway;
      systemd.enable = true;
      xwayland = true;
      wrapperFeatures.gtk = true;
      checkConfig = false;

      config = {
        modifier = mod;
        terminal = term;
        menu = "${pkgs.wofi}/bin/wofi --show drun";

        input = {
          "type:touchpad" = {
            tap = if cfg.touchpad.tap then "enabled" else "disabled";
            natural_scroll = "enabled";
            middle_emulation = "enabled";
            dwt = "disabled";
            pointer_accel = "0.4";
            accel_profile = "adaptive";
          };
          "type:keyboard" = {
            xkb_layout = cfg.keyboard.layout;
          }
          // lib.optionalAttrs (cfg.keyboard.variant != "") { xkb_variant = cfg.keyboard.variant; }
          // lib.optionalAttrs (cfg.keyboard.options != "") { xkb_options = cfg.keyboard.options; };
        };

        bars = [ ];
        startup = [
          {
            command = "${config.home.homeDirectory}/.config/waybar/launch_waybar.sh";
            always = true;
          }
          {
            # Re-apply the live theme's window colours on launch AND on every
            # `swaymsg reload` (a reload re-reads the baked config colours, which
            # would otherwise drop a runtime theme-switcher choice).
            command = ''theme-set --colors-only "$(theme-current)"'';
            always = true;
          }
        ];

        window.commands = [
          {
            criteria = {
              title = scratchTitle;
            };
            command = lib.concatStringsSep ", " [
              "floating enable"
              "sticky enable"
              "move to scratchpad"
              "border none"
            ];
          }
        ];

        keybindings =
          (lib.mkOptionDefault {
            "${mod}+Return" = "exec ${term}";
            "${mod}+q" = "kill";
            "${mod}+d" = "exec ${pkgs.wofi}/bin/wofi --show drun";

            "${mod}+i" = "exec ${config.home.homeDirectory}/.config/sway/scripts/toggle_scratchpad.sh";
            "${mod}+Shift+Return" = "exec ${term} -t ${scratchTitle} -e ${cfg.scratchpad.command}";

            "${mod}+Shift+r" = "reload";
            "${mod}+Shift+e" = ''exec sh -lc 'swaynag -t warning -m "Exit Sway?" -b "Logout" "swaymsg exit"' '';
            "${mod}+Shift+x" = "exec ${pkgs.swaylock-effects}/bin/swaylock -f";

            "${mod}+h" = "focus left";
            "${mod}+j" = "focus down";
            "${mod}+k" = "focus up";
            "${mod}+l" = "focus right";
            "${mod}+Shift+h" = "move left";
            "${mod}+Shift+j" = "move down";
            "${mod}+Shift+k" = "move up";
            "${mod}+Shift+l" = "move right";
            "${mod}+space" = "workspace back_and_forth";

            "${mod}+v" = "split v";
            "${mod}+b" = "split h";
            "${mod}+f" = "fullscreen toggle";

            # gopass launcher / store switcher (home/apps/gopass.nix) and the
            # runtime theme switcher (home/themes/theme-switcher.nix).
            "${mod}+p" = "exec gopass-launcher";
            "${mod}+Shift+p" = "exec gopass-switcher";
            "${mod}+Shift+t" = "exec theme-switcher";

            "Print" = "exec ${pkgs.flameshot}/bin/flameshot gui";

            # Audio media keys via wpctl (WirePlumber).
            "XF86AudioRaiseVolume" =
              "exec ${pkgs.wireplumber}/bin/wpctl set-volume -l 1.0 @DEFAULT_AUDIO_SINK@ 5%+";
            "XF86AudioLowerVolume" = "exec ${pkgs.wireplumber}/bin/wpctl set-volume @DEFAULT_AUDIO_SINK@ 5%-";
            "XF86AudioMute" = "exec ${pkgs.wireplumber}/bin/wpctl set-mute @DEFAULT_AUDIO_SINK@ toggle";
            "XF86AudioMicMute" = "exec ${pkgs.wireplumber}/bin/wpctl set-mute @DEFAULT_AUDIO_SOURCE@ toggle";
          })
          // lib.listToAttrs (
            map (n: {
              name = "${mod}+${toString n}";
              value = "workspace number ${toString n}";
            }) (lib.range 1 9)
          )
          // lib.listToAttrs (
            map (n: {
              name = "${mod}+Shift+${toString n}";
              value = "move container to workspace number ${toString n}";
            }) (lib.range 1 9)
          );
      };
    };
  };
}
