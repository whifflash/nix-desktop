_:
let
  colors = {
    bg = "#24283b";
    bg_alt = "#1f2335";
    surface = "#2a2f45";
    surfaceAlt = "#3b4261";
    fg = "#c0caf5";
    fg_dim = "#a9b1d6";
    gray = "#565f89";
    red = "#f7768e";
    orange = "#ff9e64";
    yellow = "#e0af68";
    green = "#9ece6a";
    aqua = "#73daca";
    blue = "#7aa2f7";
    purple = "#bb9af7";
  };
in
{
  name = "tokyonight-storm";
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
