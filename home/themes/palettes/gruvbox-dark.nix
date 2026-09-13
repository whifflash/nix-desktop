_:
let
  colors = {
    dark0 = "#282828";
    dark1 = "#3c3836";
    dark2 = "#504945";
    dark3 = "#665c54";
    dark4 = "#7c6f64";
    light0 = "#fbf1c7";
    light1 = "#ebdbb2";
    light2 = "#d5c4a1";
    light3 = "#bdae93";
    light4 = "#a89984";
    neutral_red = "#cc241d";
    neutral_green = "#98971a";
    neutral_yellow = "#d79921";
    neutral_blue = "#458588";
    neutral_purple = "#b16286";
    neutral_aqua = "#689d6a";
    neutral_orange = "#d65d0e";
    gray = "#928374";
  };
in
{
  name = "gruvbox-dark";
  tokens = {
    bg = colors.dark0;
    bgAlt = colors.dark1;
    surface = colors.dark2;
    surfaceAlt = colors.dark3;
    overlay = colors.dark4;
    fg = colors.light1;
    muted = colors.light3;
    border = colors.dark3;
    borderMuted = colors.dark2;

    primary = colors.neutral_blue;
    secondary = colors.neutral_purple;

    success = colors.neutral_green;
    warning = colors.neutral_yellow;
    error = colors.neutral_red;
    hint = colors.neutral_aqua;

    accent1 = colors.neutral_orange;
    accent2 = colors.neutral_aqua;
    accent3 = colors.neutral_purple;
  };
  raw = colors;
}
