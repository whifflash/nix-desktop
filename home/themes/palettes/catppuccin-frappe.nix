_:
let
  colors = {
    bg = "#303446";
    bg_alt = "#292c3c";
    surface = "#414559";
    surfaceAlt = "#51576d";
    fg = "#c6d0f5";
    fg_dim = "#a5adce";
    gray = "#737994";
    red = "#e78284";
    orange = "#ef9f76";
    yellow = "#e5c890";
    green = "#a6d189";
    aqua = "#81c8be";
    blue = "#8caaee";
    purple = "#ca9ee6";
  };
in
{
  name = "catppuccin-frappe";
  tokens = {
    inherit (colors) bg;
    bgAlt = colors.bg_alt;
    inherit (colors) surface;
    inherit (colors) surfaceAlt;
    overlay = colors.gray;
    inherit (colors) fg;
    muted = colors.fg_dim;
    border = colors.surfaceAlt;
    borderMuted = colors.surface;

    primary = colors.blue;
    secondary = colors.purple;

    success = colors.green;
    warning = colors.yellow;
    error = colors.red;
    hint = colors.aqua;

    accent1 = colors.orange;
    accent2 = colors.aqua;
    accent3 = colors.purple;
  };
  raw = colors;
}
