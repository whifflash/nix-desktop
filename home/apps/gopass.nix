{
  config,
  lib,
  pkgs,
  ...
}:
let
  cfg = config.dynamic.gopass;
  # The wofi launcher/switcher, Wayland clipboard and GNOME pinentry are
  # Linux-desktop only; the CLI wrappers, browser bridge and SSH askpass work on
  # macOS too (used at VALUE level only — never to shape attribute names).
  isLinux = pkgs.stdenv.hostPlatform.isLinux;

  homeDir = config.home.homeDirectory;
  configDir = "${homeDir}/.config";
  stateDir = "${homeDir}/.local/state/gopass";
  stateFile = "${stateDir}/current-store";
  storesFile = "${configDir}/gopass/stores.local";

  normalizeStore =
    store:
    if lib.hasPrefix "/" store then
      store
    else if lib.hasPrefix "~/" store then
      "${homeDir}/${lib.removePrefix "~/" store}"
    else
      "${homeDir}/${store}";

  stores = lib.unique (map normalizeStore (cfg.stores ++ [ cfg.defaultStore ]));
  defaultStore = normalizeStore cfg.defaultStore;

  currentStore = pkgs.writeShellApplication {
    name = "gopass-current-store";
    runtimeInputs = [ pkgs.coreutils ];
    text = ''
      set -euo pipefail

      state_file=${lib.escapeShellArg stateFile}
      default_store=${lib.escapeShellArg defaultStore}

      if [ -f "$state_file" ]; then
        cat "$state_file"
      else
        printf '%s\n' "$default_store"
      fi
    '';
  };

  gopassWrapper = pkgs.writeShellApplication {
    name = "gopass-selected";
    runtimeInputs = [
      pkgs.coreutils
      pkgs.gnupg
      pkgs.gopass
    ]
    ++ lib.optional isLinux pkgs.wl-clipboard; # `gopass show --clip` uses pbcopy on macOS
    text = ''
      set -euo pipefail
      store="$(${currentStore}/bin/gopass-current-store)"
      exec env PASSWORD_STORE_DIR="$store" ${pkgs.gopass}/bin/gopass "$@"
    '';
  };

  gopassJsonApiWrapper = pkgs.writeShellApplication {
    name = "gopass-jsonapi-selected";
    runtimeInputs = [
      pkgs.coreutils
      pkgs.gnupg
      pkgs.gopass-jsonapi
    ];
    text = ''
      set -euo pipefail
      store="$(${currentStore}/bin/gopass-current-store)"
      exec env PASSWORD_STORE_DIR="$store" ${pkgs.gopass-jsonapi}/bin/gopass-jsonapi "$@"
    '';
  };

  gopassLauncher = pkgs.writeShellApplication {
    name = "gopass-launcher";
    runtimeInputs = [
      pkgs.coreutils
      pkgs.findutils
      pkgs.gnugrep
      pkgs.libnotify
      pkgs.wofi
      gopassWrapper
    ];
    text = ''
      set -euo pipefail

      store="$(${currentStore}/bin/gopass-current-store)"

      if [ ! -d "$store" ]; then
        notify-send "gopass" "Store not found: $store"
        exit 1
      fi

      if [ ! -f "$store/.gpg-id" ]; then
        notify-send "gopass" "Selected store is not initialized (.gpg-id missing)"
        exit 1
      fi

      selection="$(${gopassWrapper}/bin/gopass-selected ls --flat | wofi --dmenu --matching=fuzzy --insensitive -p "$(basename "$store")")" || exit 0
      [ -n "$selection" ] || exit 0

      ${gopassWrapper}/bin/gopass-selected show --clip "$selection"
      notify-send "gopass" "Copied: $selection"
    '';
  };

  gopassSwitcher = pkgs.writeShellApplication {
    name = "gopass-switcher";
    runtimeInputs = [
      pkgs.coreutils
      pkgs.gnused
      pkgs.libnotify
      pkgs.wofi
    ];
    text = ''
      set -euo pipefail

      stores_file=${lib.escapeShellArg storesFile}
      state_dir=${lib.escapeShellArg stateDir}
      state_file=${lib.escapeShellArg stateFile}

      mkdir -p "$state_dir"

      if [ ! -f "$stores_file" ]; then
        notify-send "gopass" "No stores file found at $stores_file"
        exit 1
      fi

      new_store="$(sed '/^[[:space:]]*$/d' "$stores_file" | wofi --dmenu -p 'gopass store')" || exit 0
      [ -n "$new_store" ] || exit 0

      printf '%s\n' "$new_store" > "$state_file"
      notify-send "gopass" "Store set to: $new_store"
    '';
  };

  # ── Browser bridge (gopassbridge extension ↔ gopass-jsonapi native host) ────
  # The native host runs gopass-jsonapi against a DEDICATED gopass context
  # (GOPASS_HOMEDIR=bridgeHome) whose root is the default store and which mounts
  # every other store (bridge mounts config, below). So the browser searches ALL
  # stores at once, INDEPENDENT of the store switcher's current selection — unlike
  # the CLI wrappers, which pin PASSWORD_STORE_DIR to the active store. Launched by
  # the browser (headless, no TTY): unlocking goes through the running gpg-agent +
  # GUI pinentry (pinentry-gnome3), which need no controlling terminal.
  bridgeHome = "${stateDir}/bridge";
  nativeHostName = "com.justwatch.gopass";
  # The AMO Firefox add-on's id is the UUID; the legacy id is kept in
  # allowed_extensions too so native messaging works whichever the add-on uses.
  ffAddonId = "{eec37db0-22ad-4bf1-9068-5ae08df8c7e9}";
  ffAddonIds = [
    ffAddonId
    "gopassbridge@justwatch.com"
  ];
  chromeExtId = "kkhfnlkhiapbiehimabddjbimfaijdhk";

  gopassBridgeHost = pkgs.writeShellApplication {
    name = "gopass-bridge-host";
    runtimeInputs = [
      pkgs.coreutils
      pkgs.gnupg
      pkgs.gopass
      pkgs.gopass-jsonapi
    ];
    text = ''
      set -euo pipefail
      # Root store + all mounts come from the bridge config (bridgeConfig, below);
      # do NOT set PASSWORD_STORE_DIR — that would pin a single store and defeat
      # the whole point (searching every store at once).
      exec env \
        GOPASS_HOMEDIR=${lib.escapeShellArg bridgeHome} \
        gopass-jsonapi listen
    '';
  };

  # Bridge gopass config: root = default store, plus one mount per other store,
  # in gopass's git-config INI format (`[mounts]` with `path` = root,
  # `[mounts "name"]` for each extra). This is what makes the browser search ALL
  # stores; it lives in the bridge's own GOPASS_HOMEDIR so it never touches your
  # normal gopass config or the store switcher.
  otherStores = lib.filter (s: s != defaultStore) stores;
  mountName =
    path: lib.removePrefix "password-store-" (lib.removePrefix "." (builtins.baseNameOf path));
  bridgeConfig = lib.concatStrings (
    [ "[mounts]\npath = ${defaultStore}\n" ]
    ++ map (s: "[mounts \"${mountName s}\"]\npath = ${s}\n") otherStores
  );
  bridgeConfigFile = "${lib.removePrefix "${homeDir}/" bridgeHome}/.config/gopass/config";

  # Native-messaging manifest — same shape `gopass-jsonapi configure` emits, but
  # pointed at the all-stores bridge host above. Firefox keys on the add-on id
  # (allowed_extensions); Chromium on the extension origin (allowed_origins).
  nativeHostManifest =
    extra:
    builtins.toJSON (
      {
        name = nativeHostName;
        description = "Gopass wrapper to search and return passwords";
        path = "${gopassBridgeHost}/bin/gopass-bridge-host";
        type = "stdio";
      }
      // extra
    );

  # ── SSH: keys stay on disk, passphrases come from gopass (via SSH_ASKPASS) ───
  # gpg-agent is already the SSH agent (services.gpg-agent.enableSshSupport). Your
  # passphrase-protected keys stay at ~/.ssh/<file>; each key's PASSPHRASE lives in
  # gopass (the password / first line) at an entry YOU name — key-file name and
  # gopass-entry name are decoupled (the ssh Match block passes both). Store one:
  #   gopass insert ssh/<whatever>    # then type the key's existing passphrase
  #
  # `gopass-ssh-askpass` is the SSH_ASKPASS helper. `gopass-ssh-load <file> <entry>`
  # passes the exact gopass entry to it via $GOPASS_SSH_ENTRY; the entry is resolved
  # across ALL stores (bridge context), so "ssh/host.example/git" is found even
  # when it lives under a mount (e.g. work/ssh/host.example/git). If the helper is
  # called without $GOPASS_SSH_ENTRY (ssh itself invoking it), it falls back to
  # "ssh/<key-basename>" parsed from ssh-add's prompt.
  gopassSshAskpass = pkgs.writeShellApplication {
    name = "gopass-ssh-askpass";
    runtimeInputs = [
      pkgs.coreutils
      pkgs.gawk
      pkgs.gnugrep
      pkgs.gnupg
      pkgs.gopass
    ];
    text = ''
      set -euo pipefail
      export GOPASS_HOMEDIR=${lib.escapeShellArg bridgeHome}
      target="''${GOPASS_SSH_ENTRY:-}"
      if [ -z "$target" ]; then
        # No explicit entry: derive "ssh/<basename>" from ssh-add's prompt ($1),
        # e.g. "Enter passphrase for /home/you/.ssh/cis:" — trim the trailing
        # ":" / quote / " (will confirm each use)" and any ".pub".
        name="$(printf '%s' "''${1:-}" | awk -F/ '{print $NF}')"
        name="''${name%%[![:alnum:]._-]*}"
        name="''${name%.pub}"
        [ -n "$name" ] || exit 1
        target="ssh/$name"
      fi
      # Match the entry under any mount prefix (root or work/…, personal/…, etc.).
      entry="$(gopass ls --flat 2>/dev/null | grep -E "(^|/)''${target}\$" | head -n1 || true)"
      [ -n "$entry" ] || exit 1
      gopass show -o "$entry"
    '';
  };
  gopassSshLoad = pkgs.writeShellApplication {
    name = "gopass-ssh-load";
    runtimeInputs = [
      pkgs.coreutils
      pkgs.gawk
      pkgs.gnugrep
      pkgs.openssh
      gopassSshAskpass
    ];
    text = ''
      set -euo pipefail
      # Usage: gopass-ssh-load <keyfile> [<gopass-entry>]. Loads ~/.ssh/<keyfile>
      # into the agent, pulling its passphrase from <gopass-entry> (default, when
      # omitted: "ssh/<keyfile>"). Idempotent: skips a key already in the agent.
      name="''${1:-}"
      entry="''${2:-}"
      if [ -z "$name" ]; then
        echo "usage: gopass-ssh-load <keyfile> [<gopass-entry>]" >&2
        exit 2
      fi
      key="$HOME/.ssh/$name"
      if [ ! -f "$key" ]; then
        echo "gopass-ssh-load: no key file $key" >&2
        exit 1
      fi
      if [ -f "$key.pub" ]; then
        fp="$(ssh-keygen -lf "$key.pub" 2>/dev/null | awk '{print $2}' || true)"
        if [ -n "$fp" ] && ssh-add -l 2>/dev/null | grep -qF "$fp"; then
          exit 0 # already in the agent
        fi
      fi
      export GOPASS_SSH_ENTRY="$entry" # empty ⇒ askpass derives ssh/<basename>
      # Capture ssh-add's stderr; on success it's just "Identity added" (dropped),
      # on failure it carries the real reason ("Bad passphrase", etc.) — surface it.
      if ! err="$(SSH_ASKPASS="${gopassSshAskpass}/bin/gopass-ssh-askpass" \
        SSH_ASKPASS_REQUIRE=force \
        ssh-add "$key" </dev/null 2>&1 >/dev/null)"; then
        echo "gopass-ssh-load: FAILED to load $key" >&2
        [ -n "$err" ] && printf '  ssh-add: %s\n' "$err" >&2
        exit 1
      fi
    '';
  };

  # The per-host PINNING that uses these helpers is consumer data (which key for
  # which host). Hand-managed ~/.ssh config or programs.ssh.extraConfig — either
  # way, one block per host:
  #   Match host git.example.com exec "gopass-ssh-load identities/example_git ssh/example/git || true"
  #       IdentityFile ~/.ssh/identities/example_git
  #       IdentitiesOnly yes
  # arg1 = the private key path under ~/.ssh/ (may be nested); arg2 = the gopass
  # passphrase entry (any depth), resolved across all stores so a mount is found.
  # Call `gopass-ssh-load` by name — it's on PATH via home.packages, so no
  # /nix/store path goes stale in a static config.
in
{
  options.dynamic.gopass = {
    stores = lib.mkOption {
      type = lib.types.listOf lib.types.str;
      default = [ "~/.password-store" ];
      description = ''
        gopass store directories (absolute, `~/…`, or relative to $HOME). The
        store switcher (gopass-switcher) picks the CLI's active one; the browser
        bridge and the SSH askpass search ALL of them at once.
      '';
    };
    defaultStore = lib.mkOption {
      type = lib.types.str;
      default = "~/.password-store";
      description = "Store active before the first switch, and the browser bridge's root mount.";
    };
    browserBridge.enable = lib.mkOption {
      type = lib.types.bool;
      default = true;
      description = ''
        Wire the gopassbridge browser extension: native-messaging hosts for
        Firefox and Chromium, plus auto-install of the extension into whichever
        of programs.firefox / programs.chromium is enabled.
      '';
    };
  };

  config = {
    home = {
      packages = [
        pkgs.gopass
        pkgs.gopass-jsonapi
        pkgs.gnupg
        currentStore
        gopassWrapper
        gopassJsonApiWrapper
        gopassSshLoad
        gopassSshAskpass # on PATH for manual testing/inspection
      ]
      ++ lib.optionals isLinux [
        pkgs.libnotify
        pkgs.wl-clipboard
        pkgs.wofi
        gopassLauncher
        gopassSwitcher
      ]
      ++ lib.optional cfg.browserBridge.enable gopassBridgeHost;

      # All home-managed files in ONE definition (a Nix attrset can't mix
      # `home.file.x = …` with `home.file = {…}`): the gopass CLI shims, and — when
      # the bridge is on — the Firefox native-messaging manifest and the bridge's
      # all-stores mounts config.
      file = {
        ".local/bin/gopass" = {
          executable = true;
          text = ''
            #!/usr/bin/env bash
            exec ${gopassWrapper}/bin/gopass-selected "$@"
          '';
        };
        ".local/bin/gopass-jsonapi" = {
          executable = true;
          text = ''
            #!/usr/bin/env bash
            exec ${gopassJsonApiWrapper}/bin/gopass-jsonapi-selected "$@"
          '';
        };
      }
      // lib.optionalAttrs cfg.browserBridge.enable {
        ".mozilla/native-messaging-hosts/${nativeHostName}.json".text = nativeHostManifest {
          allowed_extensions = ffAddonIds;
        };
        "${bridgeConfigFile}".text = bridgeConfig;
      };

      activation.gopassState = lib.hm.dag.entryAfter [ "writeBoundary" ] ''
        mkdir -p ${lib.escapeShellArg stateDir}
        if [ ! -f ${lib.escapeShellArg stateFile} ]; then
          printf '%s\n' ${lib.escapeShellArg defaultStore} > ${lib.escapeShellArg stateFile}
        fi
      '';

      sessionVariables.PASSWORD_STORE_DIR = defaultStore;
    };

    xdg = {
      configFile = {
        "gopass/stores.local".text = lib.concatStringsSep "\n" stores + "\n";
      }
      // lib.optionalAttrs cfg.browserBridge.enable {
        # Chromium native-messaging manifest (per-user — no /etc, no sudo).
        "chromium/NativeMessagingHosts/${nativeHostName}.json".text = nativeHostManifest {
          allowed_origins = [ "chrome-extension://${chromeExtId}/" ];
        };
      };

      desktopEntries = lib.mkIf isLinux {
        gopass-launcher = {
          name = "Gopass Launcher";
          exec = "${gopassLauncher}/bin/gopass-launcher";
          terminal = false;
          categories = [ "Utility" ];
        };
        gopass-switcher = {
          name = "Gopass Store Switcher";
          exec = "${gopassSwitcher}/bin/gopass-switcher";
          terminal = false;
          categories = [ "Utility" ];
        };
      };
    };

    programs = {
      # Auto-install the extension where a managed browser is enabled. The Firefox
      # policy key MUST be the installed add-on's real id (the AMO UUID), or Firefox
      # rejects the entry.
      firefox.policies.ExtensionSettings =
        lib.mkIf (cfg.browserBridge.enable && config.programs.firefox.enable)
          {
            ${ffAddonId} = {
              install_url = "https://addons.mozilla.org/firefox/downloads/latest/${ffAddonId}/latest.xpi";
              installation_mode = "normal_installed";
            };
          };
      chromium.extensions = lib.mkIf (cfg.browserBridge.enable && config.programs.chromium.enable) [
        chromeExtId
      ];
      gpg.enable = true;
    };

    services.gpg-agent = {
      enable = true;
      enableSshSupport = true;
      # GUI pinentry so headless callers (browser bridge, ssh-add via askpass)
      # can unlock without a TTY. Consumers may override.
      pinentry.package = lib.mkDefault (if isLinux then pkgs.pinentry-gnome3 else pkgs.pinentry_mac);
    };
  };
}
