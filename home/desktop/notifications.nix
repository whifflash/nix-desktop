{
  config,
  lib,
  pkgs,
  ...
}:
let
  t = config.dynamic.theme.tokens;
  # Inline the palette (@define-color …) instead of @import-ing palette.css. A
  # store-symlinked style.css + relative @import is fragile: swaync/GTK can
  # resolve "palette.css" against the /nix/store dir (where it doesn't exist)
  # and then drop the WHOLE stylesheet, falling back to swaync's default look.
  # Inlining is self-contained and always parses. Colours are the build-time
  # scheme (they re-theme on `task switch`, not live via the switcher).
  paletteInline = lib.concatStrings (
    lib.mapAttrsToList (name: hex: "@define-color ${name} ${hex};\n") t
  );
in
{
  config = lib.mkIf config.dynamic.desktop.enable {
    # Notification daemon with a Do-Not-Disturb toggle + notification center.
    #
    # The Waybar button (custom/notifications, top-left of the top bar) drives
    # this via `swaync-client`:
    #   left-click  -> toggle DnD  (`-d`)  = mute / unmute
    #   right-click -> open center (`-t`)  = review notifications that arrived
    #                                        while muted (nothing is lost)
    # Waybar reflects the state through `swaync-client -swb`, and its CSS greys
    # the icon out while muted (see dotfiles/waybar/style.css).
    services.swaync = {
      enable = true;

      settings = {
        positionX = "right";
        positionY = "top";
        control-center-positionX = "right";
        control-center-positionY = "top";
        layer = "overlay";
        control-center-layer = "top";
        cssPriority = "user"; # let our style.css win over swaync's defaults
        notification-icon-size = 48;
        notification-window-width = 420;
        timeout = 8;
        timeout-low = 4;
        timeout-critical = 0;
        keyboard-shortcuts = true;
        image-visibility = "when-available";
        # Keep the center populated so muted notifications can be reviewed later.
        hide-on-clear = false;
        hide-on-action = true;
      };

      # Themed from the active palette, inlined as @define-color entries (see the
      # paletteInline binding above) so the stylesheet is self-contained and never
      # depends on a resolvable @import.
      style = ''
        ${paletteInline}

        /* NOTE on the inner border: libadwaita forces a 1px accent border on each
         * notification's inner boxes, at a GTK priority no swaync stylesheet can
         * override — tried exhaustively (named + custom accent colours, border:none,
         * outline/box-shadow resets, !important); only the GTK inspector's
         * max-priority ever beat it. So the border shows in the GTK accent colour
         * (the theme's accent). Darkening the GTK accent to hide it (base0D in
         * hm-stylix-bridge.nix) worked visually but broke accent links/text in other
         * GTK apps (Evolution → dark-on-dark), so that was reverted. We accept the
         * border; it's most visible on the coloured critical/low cards. */

        * {
          font-family: "RobotoMono Nerd Font", "Font Awesome 7 Free";
          font-size: 13px;
        }

        /* ── Control center panel ───────────────────────────────────────── */
        .control-center {
          background: @bg;
          color: @fg;
          border: 1px solid @border;
          border-radius: 0;
        }
        .control-center-list { background: transparent; }

        .widget-title { color: @fg; margin: 8px; font-weight: bold; }
        .widget-title > button {
          background: @surface;
          color: @fg;
          border: none;
          border-radius: 0;
          padding: 4px 10px;
        }

        .widget-dnd { color: @fg; margin: 8px; }
        .widget-dnd > switch {
          background: @surface;
          border-radius: 0;
        }
        .widget-dnd > switch:checked { background: @accent1; }

        /* ── Popup transparency fix ─────────────────────────────────────── */
        /* Only the card (.notification) paints. Keep the floating window and the
         * wrappers transparent so no opaque square shows behind the card. Inner
         * elements are transparent too, so a rounded card (presets B/C) clips
         * cleanly with no square corners inside it. */
        .floating-notifications.background,
        .notification-row,
        .notification-background,
        .notification-default-action,
        .notification-content {
          background: transparent;
          box-shadow: none;
        }

        /* ── The notification card — solid surface + left accent bar ──────────
         * A clean rounded surface card with a coloured strip down the left edge,
         * drawn as a hard-stop background gradient (part of the card's paint, not a
         * border). The bar colour signals urgency: @accent1 (orange) normal, @error
         * (red) critical, @success (green) low. `border: none` drops swaync's own
         * default card border; libadwaita's thin accent border on the INNER boxes
         * stays (it genuinely can't be removed or recoloured per-app — see the note
         * up top; we accept it). Rounded corners come from swaync's default (we no
         * longer force border-radius:0). The plain `background:` line is a fallback
         * if a GTK build rejects the gradient (card stays solid, just no bar). Set on
         * the winning 3-class chain (a bare `.notification` loses to swaync's
         * default). Bar width / text gap: the `4px` stop and the left padding. */
        .notification-row .notification-background .notification {
          background: @surface;
          background: linear-gradient(to right, @accent1 4px, @surface 4px);
          color: @fg;
          border: none;
          margin: 6px 8px;
          padding: 8px 8px 8px 14px;
        }
        .notification-row .notification-background .notification.critical {
          background: @surface;
          background: linear-gradient(to right, @error 4px, @surface 4px);
        }
        .notification-row .notification-background .notification.low {
          background: @surface;
          background: linear-gradient(to right, @success 4px, @surface 4px);
        }

        /* ── Card internals ─────────────────────────────────────────────── */
        .notification-content { color: @fg; padding: 8px; }
        .summary { color: @fg; font-weight: bold; }
        .time { color: @muted; }
        .body { color: @muted; }

        /* ── Action buttons (per-notification actions) ──────────────────── */
        .notification-action {
          background: @surface;
          color: @fg;
          border: 1px solid @border;
          border-radius: 0;
          margin: 4px;
          padding: 4px 8px;
        }
        .notification-action:hover { background: @accent1; color: @bg; }

        /* ── Inline reply (text entry + send) ───────────────────────────── */
        .inline-reply-entry {
          background: @bg;
          color: @fg;
          border: 1px solid @border;
          border-radius: 0;
          margin: 4px;
          padding: 4px 6px;
        }
        .inline-reply-entry:focus { border-color: @accent1; }
        .inline-reply-button {
          background: @surface;
          color: @fg;
          border: 1px solid @border;
          border-radius: 0;
          margin: 4px;
          padding: 4px 8px;
        }
        .inline-reply-button:hover { background: @accent1; color: @bg; }

        /* ── Close button ───────────────────────────────────────────────── */
        /* Close button — pushed INSIDE the card. swaync's default sits at
         * margin-top/right 8px, but the card's own margin (6/8) + rounded corners
         * let it overhang the top-right. Larger top/right margins seat it clear of
         * the corner, on the card fill. */
        .close-button {
          background: @bg;
          color: @fg;
          border: none;
          border-radius: 0;
          margin: 16px 16px 0 0;
          padding: 2px 6px;
        }
        .close-button:hover { background: @error; color: @bg; }
      '';
    };

    # swaync is ALSO D-Bus-activated as org.freedesktop.Notifications, so it can
    # run outside this systemd unit (in a separate cgroup). That is why
    # `systemctl restart swaync` never touched the running daemon and the styling
    # never refreshed. Make the unit authoritative and self-refreshing:
    #   * ExecStartPre kills any stray (D-Bus-activated) swaync, so a (re)start of
    #     this unit always ends up owning the process + the notification bus name.
    #   * X-Restart-Triggers ties the unit's identity to the stylesheet, so
    #     `task switch` restarts swaync automatically whenever the CSS changes —
    #     no manual pkill/reload needed.
    #
    # GOTCHA: on NixOS `bin/swaync` is a Nix wrapper that exec()s the real ELF, so
    # the running daemon's process name (comm) is `.swaync-wrapped`, NOT `swaync`.
    # `pkill -x swaync` therefore matched NOTHING and the stray never died — every
    # "restart" then hit "An instance of SwayNotificationCenter is already
    # running!" and served stale CSS. Match BOTH names (the plain one covers a
    # future unwrapped build). `-x` anchors to the whole comm, so neither pattern
    # touches the long-lived `.swaync-client-` subscriber that feeds Waybar's
    # notification indicator (its comm is `.swaync-client-`, 15 chars). The leading
    # `-` lets each pkill exit non-zero (nothing to kill) without failing start.
    systemd.user.services.swaync = {
      Service.ExecStartPre = lib.mkForce [
        "-${pkgs.procps}/bin/pkill -x swaync"
        "-${pkgs.procps}/bin/pkill -x .swaync-wrapped"
      ];
      Unit.X-Restart-Triggers = [ (builtins.hashString "sha256" config.services.swaync.style) ];
    };
  };
}
