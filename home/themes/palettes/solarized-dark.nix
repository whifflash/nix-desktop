_:
let
  base = {
    base03 = "#002b36";
    base02 = "#073642";
    base01 = "#586e75";
    base00 = "#657b83";
    base0 = "#839496";
    base1 = "#93a1a1";
    base2 = "#eee8d5";
    base3 = "#fdf6e3";
    yellow = "#b58900";
    orange = "#cb4b16";
    red = "#dc322f";
    magenta = "#d33682";
    violet = "#6c71c4";
    blue = "#268bd2";
    cyan = "#2aa198";
    green = "#859900";
  };
in
{
  name = "solarized-dark";
  tokens = {
    bg = base.base03;
    bgAlt = base.base02;
    surface = base.base01;
    surfaceAlt = base.base00;
    overlay = base.base0;
    fg = base.base0;
    muted = base.base1;
    border = base.base00;
    borderMuted = base.base01;

    primary = base.blue;
    secondary = base.violet;

    success = base.green;
    warning = base.yellow;
    error = base.red;
    hint = base.cyan;

    accent1 = base.orange;
    accent2 = base.cyan;
    accent3 = base.violet;
  };
  raw = base;
}
