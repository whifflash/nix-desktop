{
  config,
  options,
  lib,
  pkgs,
  ...
}:
let
  inherit (lib) mkOption mkIf types;
  cfg = config.services.repo-sync;
  isDarwin = pkgs.stdenv.hostPlatform.isDarwin;
  home = config.home.homeDirectory;

  # The forge-agnostic sync engine (Gitea / GitLab / GitHub): lists every
  # non-archived repository the token can see, clones the missing ones
  # (depth 1) and fast-forwards the rest, pinning the forge's SSH host key.
  syncScript = pkgs.writeShellApplication {
    name = "repo-sync";
    runtimeInputs = with pkgs; [
      coreutils
      curl
      jq
      git
      openssh
      gnused
      gnugrep
    ];
    text = builtins.readFile ./repo-sync/sync.sh;
  };

  # One wrapper per instance with its settings baked in, so systemd and launchd
  # run the same thing and there is exactly one code path for env handling.
  mkWrapper =
    name: i:
    pkgs.writeShellApplication {
      name = "repo-sync-${name}";
      runtimeInputs = [
        pkgs.coreutils
        syncScript
      ];
      text = ''
        set -euo pipefail

        ${lib.optionalString (i.randomizedDelaySec > 0) ''
          # Spread runs out (what systemd's RandomizedDelaySec would do; kept here
          # so macOS launchd behaves the same).
          sleep "$(shuf -i 0-${toString i.randomizedDelaySec} -n 1)"
        ''}

        install -m 700 -d ${lib.escapeShellArg i.stateDir}
        install -m 755 -d ${lib.escapeShellArg i.destDir}

        # TOKEN=… comes from a runtime file the consumer provisions (sops etc.).
        env_file=${lib.escapeShellArg i.environmentFile}
        if [ ! -r "$env_file" ]; then
          echo "repo-sync-${name}: environment file not readable: $env_file" >&2
          exit 78
        fi
        set -a
        # shellcheck disable=SC1090
        . "$env_file"
        set +a
        if [ -z "''${TOKEN:-}" ]; then
          echo "repo-sync-${name}: TOKEN missing after sourcing $env_file" >&2
          exit 78
        fi

        export FORGE=${lib.escapeShellArg i.forge}
        export BASE_URL=${lib.escapeShellArg i.baseUrl}
        export DEST_DIR=${lib.escapeShellArg i.destDir}
        export STATE_DIR=${lib.escapeShellArg i.stateDir}
        export LOG_LEVEL=${lib.escapeShellArg i.logLevel}
        export SSH_PORT=${toString i.sshPort}
        ${lib.optionalString (i.sshHost != null) "export SSH_HOST=${lib.escapeShellArg i.sshHost}"}
        # Never block on a prompt from a timer.
        export GIT_TERMINAL_PROMPT=0
        export SSH_ASKPASS_REQUIRE=never

        exec repo-sync
      '';
    };

  enabled = lib.filterAttrs (_: i: i.enable) cfg.instances;
  unitName = name: "repo-sync-${name}";
in
{
  options.services.repo-sync.instances = mkOption {
    default = { };
    description = ''
      Periodic "clone everything my token can see" jobs, one per forge account.
      Linux: a systemd user service + timer per instance (journal-logged).
      macOS: a launchd user agent per instance (logs under ~/Library/Logs).
      The token is read at run time from `environmentFile`; how that file is
      provisioned (sops-nix, agenix, …) is the consumer's business.
    '';
    type = types.attrsOf (
      types.submodule (
        { name, ... }:
        {
          options = {
            enable = mkOption {
              type = types.bool;
              default = true;
              description = "Whether this instance is active.";
            };
            forge = mkOption {
              type = types.enum [
                "gitea"
                "gitlab"
                "github"
              ];
              default = "gitea";
              description = "API dialect. gitea: /api/v1/user/repos; gitlab: /api/v4/projects?membership=true; github: /user/repos.";
            };
            baseUrl = mkOption {
              type = types.str;
              example = "https://git.example.com";
              description = "Forge base URL (for github: https://api.github.com).";
            };
            destDir = mkOption {
              type = types.str;
              default = "${home}/git/${name}";
              defaultText = lib.literalExpression ''"''${config.home.homeDirectory}/git/<name>"'';
              description = "Where repositories land: <destDir>/<owner-or-group-path>/<repo>.";
            };
            environmentFile = mkOption {
              type = types.str;
              example = "/run/secrets/gitea-token.env";
              description = "Runtime file exporting `TOKEN=<personal access token>` (read_api / read_repository scope). Sourced at run time, never copied into the store.";
            };
            sshHost = mkOption {
              type = types.nullOr types.str;
              default = null;
              description = "Host whose SSH key gets pinned (ssh-keyscan) for cloning. Default: the host of baseUrl (github.com for the github forge).";
            };
            sshPort = mkOption {
              type = types.port;
              default = 22;
              description = "SSH port of the forge (Gitea often 2222). Used for the key scan; clone URLs from the API carry their own port.";
            };
            intervalSec = mkOption {
              type = types.ints.positive;
              default = 3600;
              description = "Seconds between runs (systemd OnUnitActiveSec / launchd StartInterval).";
            };
            randomizedDelaySec = mkOption {
              type = types.ints.unsigned;
              default = 600;
              description = "Random delay before each run, in seconds (0 disables).";
            };
            logLevel = mkOption {
              type = types.enum [
                "DEBUG"
                "INFO"
                "WARN"
                "ERROR"
              ];
              default = "INFO";
              description = "Verbosity of the sync log.";
            };
            stateDir = mkOption {
              type = types.str;
              default =
                if isDarwin then
                  "${home}/Library/Application Support/repo-sync/${name}"
                else
                  "${home}/.local/state/repo-sync/${name}";
              defaultText = "~/.local/state/repo-sync/<name> (Linux) · ~/Library/Application Support/repo-sync/<name> (macOS)";
              description = "Holds the pinned known_hosts.";
            };
          };
        }
      )
    );
  };

  # Platform split, carefully: the attribute NAMES of `config` may only depend on
  # what is *declared* (`options ? …`) — never on `pkgs`, which home-manager
  # resolves through `_module.args` (→ infinite recursion). A definition for an
  # undeclared option is rejected even under a false mkIf, so `systemd.user`
  # (absent on macOS) and `launchd` (possibly absent on Linux) are added with
  # optionalAttrs on declaration, and additionally gated by platform at VALUE
  # level with mkIf.
  config = mkIf (enabled != { }) (
    {
      home.packages = [ syncScript ] ++ lib.mapAttrsToList mkWrapper enabled;
    }
    // lib.optionalAttrs (options ? systemd) {
      systemd.user.services = mkIf (!isDarwin) (
        lib.mapAttrs' (
          name: i:
          lib.nameValuePair (unitName name) {
            Unit = {
              Description = "Sync repositories from ${i.baseUrl} (${i.forge})";
              After = [ "network-online.target" ];
              Wants = [ "network-online.target" ];
            };
            Service = {
              Type = "oneshot";
              ExecStart = "${mkWrapper name i}/bin/${unitName name}";
              SyslogIdentifier = unitName name;
            };
          }
        ) enabled
      );

      systemd.user.timers = mkIf (!isDarwin) (
        lib.mapAttrs' (
          name: i:
          lib.nameValuePair (unitName name) {
            Unit.Description = "Timer: sync repositories from ${i.baseUrl}";
            Timer = {
              OnBootSec = "5m";
              OnUnitActiveSec = "${toString i.intervalSec}s";
              Persistent = true; # catch up after suspend / a missed window
            };
            Install.WantedBy = [ "timers.target" ];
          }
        ) enabled
      );
    }
    // lib.optionalAttrs (options ? launchd) {
      launchd.agents = mkIf isDarwin (
        lib.mapAttrs' (
          name: i:
          lib.nameValuePair (unitName name) {
            enable = true;
            config = {
              ProgramArguments = [ "${mkWrapper name i}/bin/${unitName name}" ];
              RunAtLoad = true;
              StartInterval = i.intervalSec;
              StandardOutPath = "${home}/Library/Logs/${unitName name}.log";
              StandardErrorPath = "${home}/Library/Logs/${unitName name}.err.log";
              ExitTimeOut = 300;
            };
          }
        ) enabled
      );
    }
  );
}
