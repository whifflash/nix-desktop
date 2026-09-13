{
  # Option interface between the host and the shared desktop layer
  # (ui.theme, ui.waybar) plus the system Stylix bridge.
  imports = [
    ./theme.nix
    ./desktop.nix
    ./stylix-bridge.nix
  ];
}
