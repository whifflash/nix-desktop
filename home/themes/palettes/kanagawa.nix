_:
let
  colors = {
    bg = "#1f1f28";
    bg_alt = "#16161d";
    surface = "#2a2a37";
    surfaceAlt = "#363646";
    fg = "#dcd7ba";
    fg_dim = "#c8c093";
    gray = "#727169";
    red = "#c34043";
    orange = "#ffa066";
    yellow = "#c0a36e";
    green = "#98bb6c";
    aqua = "#7fb4ca";
    blue = "#7e9cd8";
    purple = "#957fb8";
  };
in
{
  name = "kanagawa";
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
