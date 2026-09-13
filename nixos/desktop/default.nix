{
  # Wayland desktop modules. Always safe to import: sway.nix / niri.nix gate on
  # programs.{sway,niri}.enable, wayland-common.nix on desktop.wayland.enable
  # (set by whichever WM is on).
  imports = [
    ./wayland-common.nix
    ./sway.nix
    ./niri.nix
  ];
}
