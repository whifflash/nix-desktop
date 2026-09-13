# Single source of truth for Sway window colours: the ordered
# [border, background, text, indicator, childBorder] token names per client
# class. Consumed by both sway-colors.nix (the baked home-manager
# `wayland.windowManager.sway.config.colors` attrset) and tokens.nix
# `mkSwayColors` (the live `swaymsg client.*` form used by theme-set), so the two
# forms can never drift. Keys are home-manager's camelCase class names;
# `swayClass` is the `swaymsg`/config-file spelling where it differs.
{
  focused = {
    swayClass = "focused";
    roles = [
      "primary"
      "surfaceAlt"
      "fg"
      "primary"
      "primary"
    ];
  };
  focusedInactive = {
    swayClass = "focused_inactive";
    roles = [
      "border"
      "bgAlt"
      "muted"
      "borderMuted"
      "border"
    ];
  };
  unfocused = {
    swayClass = "unfocused";
    roles = [
      "borderMuted"
      "bg"
      "muted"
      "borderMuted"
      "borderMuted"
    ];
  };
  urgent = {
    swayClass = "urgent";
    roles = [
      "error"
      "error"
      "bg"
      "error"
      "error"
    ];
  };
  placeholder = {
    swayClass = "placeholder";
    roles = [
      "borderMuted"
      "surface"
      "fg"
      "borderMuted"
      "borderMuted"
    ];
  };
}
