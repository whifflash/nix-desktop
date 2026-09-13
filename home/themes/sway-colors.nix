{
  lib,
  config,
  ...
}:
let
  T = config.dynamic.theme.tokens;

  # Single source shared with tokens.nix's mkSwayColors (the live swaymsg form).
  roles = import ./sway-color-roles.nix;

  # home-manager colour-class fields, in the order the role lists use.
  fields = [
    "border"
    "background"
    "text"
    "indicator"
    "childBorder"
  ];
  mkClass =
    r: lib.listToAttrs (lib.zipListsWith (f: tok: lib.nameValuePair f T.${tok}) fields r.roles);
in
{
  wayland.windowManager.sway.config.colors = lib.mkForce (lib.mapAttrs (_: mkClass) roles);
}
