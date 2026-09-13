_:
let
  colors = {
    bg = "#2b3339";
    bg_dim = "#232a2e";
    bg2 = "#3a4248";
    bg3 = "#454d53";
    fg = "#d3c6aa";
    fg_dim = "#a7c080";
    gray = "#7a8478";
    red = "#e67e80";
    orange = "#e69875";
    yellow = "#dbbc7f";
    green = "#a7c080";
    aqua = "#83c092";
    blue = "#7fbbb3";
    purple = "#d699b6";
  };
in
{
  name = "everforest-dark";
  tokens = {
    inherit (colors) bg;
    bgAlt = colors.bg_dim;
    surface = colors.bg2;
    surfaceAlt = colors.bg3;
    overlay = colors.gray;
    inherit (colors) fg;
    muted = colors.fg_dim;
    border = colors.bg3;
    borderMuted = colors.bg2;

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
