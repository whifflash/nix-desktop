# Shared palette helpers — the single source for palette discovery/loading and
# the semantic-token → base16 mapping. Consumed by:
#   - tokens.nix                     (home: resolves the active palette + renders)
#   - hm-stylix-bridge.nix           (home Stylix base16Scheme)
#   - modules/ui/stylix-bridge.nix   (system Stylix base16Scheme)
# so the palette set and the token→base16 map can't drift between them.
{ lib }:
let
  palettesDir = ./palettes;

  available = map (n: lib.removeSuffix ".nix" n) (
    builtins.filter (n: lib.hasSuffix ".nix" n) (
      builtins.attrNames (lib.filterAttrs (_: v: v == "regular") (builtins.readDir palettesDir))
    )
  );

  loadPalette =
    name:
    let
      p = palettesDir + "/${name}.nix";
    in
    if builtins.pathExists p then
      import p { }
    else
      throw "theme: palette '${name}' not found. Available: ${lib.concatStringsSep ", " available}";

  # Semantic tokens → base16 (base00..base0F). `g` falls back so an incomplete
  # palette never throws (all shipped palettes define the full set).
  toBase16 =
    tokens:
    let
      g = n: tokens.${n} or "#555555";
    in
    {
      base00 = g "bg";
      base01 = g "bgAlt";
      base02 = g "surface";
      base03 = g "surfaceAlt";
      base04 = g "muted";
      base05 = g "fg";
      base06 = g "fg";
      base07 = g "overlay";
      base08 = g "error";
      base09 = g "accent1";
      base0A = g "warning";
      base0B = g "success";
      base0C = g "hint";
      base0D = g "primary";
      base0E = g "secondary";
      base0F = g "accent3";
    };
in
{
  inherit
    palettesDir
    available
    loadPalette
    toBase16
    ;
}
