{
  # Everything home-side EXCEPT the config.toml feed (import
  # homeManagerModules.hostcfg-feed separately if you use the TOML model).
  imports = [
    ./themes
    ./desktop
    ./apps
    ./services/repo-sync.nix
  ];
}
