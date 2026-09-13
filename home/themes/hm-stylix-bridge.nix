{
  lib,
  config,
  options,
  osConfig ? { },
  ...
}:
let
  # Follows the host's ui.theme.stylix.enable (the system Stylix bridge keys on
  # the same option), so both layers agree via the shared option interface.
  enabled = lib.attrByPath [ "ui" "theme" "stylix" "enable" ] false osConfig;

  # base16 (base00..base0F) from the shared token→base16 map; scheme/author here.
  # NOTE: do NOT override base0D (the accent) to a dark colour. base0D is the
  # libadwaita ACCENT — used for links, selected text and accent foregrounds in
  # GTK apps (Evolution, file managers, …). Pointing it at @surface once made the
  # swaync notification border blend, but it also turned every accent link/label
  # in those apps into dark-on-dark and rendered Evolution unreadable. The accent
  # must stay a bright, readable palette colour; leave base0D = t.primary (default).
  palettes = import ./palette-lib.nix { inherit lib; };
  base16 = palettes.toBase16 config.dynamic.theme.tokens // {
    scheme = config.dynamic.theme.paletteName;
    author = "generated";
  };

  # Stylix's HM module is only present when the consumer imports it (the NixOS
  # Stylix module injects it). Definitions for an undeclared `stylix` option are
  # rejected even under a false mkIf, so gate with optionalAttrs.
  hasStylix = options ? stylix;
in
{
  config = lib.mkIf enabled (
    lib.optionalAttrs hasStylix {
      stylix = {
        base16Scheme = base16;
        targets = {
          gtk.enable = true;
          sway.enable = false;
          swaylock.enable = false;
          # Alacritty is themed dynamically from tokens (see ./apps.nix + the live
          # colors.toml import); keep Stylix from baking a static [colors] block
          # that would override the runtime theme.
          alacritty.enable = false;
          # Required since stylix started gating firefox theming on explicit profile names.
          firefox.profileNames = [ "default" ];
        };
      };

      # Pin GTK4 to the GTK3/general theme (guards against HM 26.05 switching the
      # gtk4 theme default to null). Stylix's own GTK target — enabled just above —
      # also defines gtk.gtk4.theme.package with the same adw-gtk3 value, so the two
      # collide at equal priority ("defined multiple times"). mkForce makes this the
      # single authoritative definition; the value is identical, so it only resolves
      # the priority clash.
      gtk.gtk4.theme = lib.mkForce config.gtk.theme;
    }
  );
}
