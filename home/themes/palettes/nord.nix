_:
let
  colors = {
    bg = "#2e3440";
    bg_alt = "#3b4252";
    surface = "#434c5e";
    surfaceAlt = "#4c566a";
    fg = "#e5e9f0";
    fg_dim = "#d8dee9";
    gray = "#4c566a";
    red = "#bf616a";
    orange = "#d08770";
    yellow = "#ebcb8b";
    green = "#a3be8c";
    aqua = "#88c0d0";
    blue = "#81a1c1";
    purple = "#b48ead";
  };
in
{
  name = "nord";
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
