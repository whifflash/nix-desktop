_:
let
  colors = {
    bg = "#24273a";
    bg_alt = "#1e2030";
    surface = "#363a4f";
    surfaceAlt = "#494d64";
    border = "#5b6078";
    overlay = "#6e738d";
    fg = "#cad3f5";
    fg_dim = "#a5adcb";
    gray = "#6e738d";
    red = "#ed8796";
    orange = "#f5a97f";
    yellow = "#eed49f";
    green = "#a6da95";
    aqua = "#8bd5ca";
    blue = "#8aadf4";
    sapphire = "#7dc4e4";
    purple = "#c6a4f4";
    teal = "#8bd5ca";
  };
in
{
  name = "catppuccin-macchiato";
  tokens = {
    inherit (colors) bg;
    bgAlt = colors.bg_alt;
    inherit (colors) surface;
    inherit (colors) surfaceAlt;
    inherit (colors) overlay;
    inherit (colors) fg;
    muted = colors.fg_dim;
    inherit (colors) border;
    borderMuted = colors.surfaceAlt;

    primary = colors.teal;
    secondary = colors.purple;

    success = colors.green;
    warning = colors.yellow;
    error = colors.red;
    hint = colors.sapphire;

    accent1 = colors.orange;
    accent2 = colors.teal;
    accent3 = colors.purple;
  };
  raw = colors;
}
