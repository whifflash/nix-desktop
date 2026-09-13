{
  # Everything system-side EXCEPT the config.toml feed (import
  # nixosModules.hostcfg-feed separately if you use the TOML model).
  imports = [
    ./ui
    ./desktop
  ];
}
