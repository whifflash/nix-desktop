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
    neutral_red = "#9d0006";
    neutral_green = "#79740e";
    neutral_yellow = "#b57614";
    neutral_blue = "#076678";
    neutral_purple = "#8f3f71";
    neutral_aqua = "#427b58";
    neutral_orange = "#af3a03";
    gray = "#928374";
  };
in
{
  name = "gruvbox-light";
  tokens = {
    bg = colors.light0;
    bgAlt = colors.light1;
    surface = colors.light2;
    surfaceAlt = colors.light3;
    overlay = colors.light4;
    fg = colors.dark1;
    muted = colors.dark3;
    border = colors.light3;
    borderMuted = colors.light2;

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
