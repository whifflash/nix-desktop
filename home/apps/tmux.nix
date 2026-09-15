{ lib, pkgs, ... }:
let
  resurrectScripts = "${pkgs.tmuxPlugins.resurrect}/share/tmux-plugins/resurrect/scripts";

  # Drop-down launcher: RESTORE BEFORE ATTACH.
  #
  # Why: the old default (`tmux new-session -A -s scratch`) started the server,
  # created a fresh "scratch" and attached the client all at once, and only
  # THEN did continuum fire a background restore ~1s later. That restore had to
  # merge into a session the client was already attached to (resurrect's
  # fragile overwrite-the-first-pane path), inside continuum's 10s "just
  # started" window, while its switch-client calls yanked the live client
  # around. Any hiccup = partial restore, lost window names, or a stuck
  # spinner. It was racy by design, which is why it kept "stopping working".
  #
  # Now, on a COLD server (fresh boot / after kill-server) this launcher brings
  # tmux up detached with a throwaway placeholder, runs resurrect's own
  # restore.sh synchronously and HEADLESSLY (no client to race, no visible
  # spinner), then attaches to the fully restored "scratch". On a WARM server
  # it just attaches. Restore is deterministic and complete before you ever see
  # the session; continuum's auto-restore is turned off so nothing races us.
  # Full fidelity is kept (contents, programs, names) because it is the very
  # same restore.sh, just driven at the right moment.
  tmuxScratch = pkgs.writeShellApplication {
    name = "tmux-scratch";
    runtimeInputs = [
      pkgs.tmux
      pkgs.coreutils
    ];
    text = ''
      session=scratch
      boot=__scratch_boot__
      scripts=${resurrectScripts}

      # The drop-down is launched by the compositor, never from inside tmux;
      # make sure a stray TMUX can't make `attach` refuse to nest.
      unset TMUX

      if ! tmux has-session 2>/dev/null; then
        # COLD START: server not running. Bring it up detached with a throwaway
        # placeholder, restore synchronously + headlessly, THEN attach.
        echo "tmux-scratch: restoring saved session..." >&2
        tmux new-session -d -s "$boot"

        # Wait (briefly) until tmux.conf + plugins are sourced so resurrect's
        # options are in place before we restore.
        for _ in $(seq 1 30); do
          [ "$(tmux show -gv @resurrect-capture-pane-contents 2>/dev/null || true)" = on ] && break
          sleep 0.1
        done

        # resurrect's restore.sh derives the server socket from $TMUX, so hand
        # it the live socket. It no-ops when there is no save yet. Its exit
        # status is ignored on purpose: with no client attached its
        # switch-client calls fail harmlessly (it has no `set -e`), and
        # `timeout` guarantees a stuck restore can never wedge the drop-down.
        sock=$(tmux display-message -p '#{socket_path}')
        TMUX="$sock,0,0" timeout 90 "$scripts/restore.sh" || true

        if tmux has-session -t "=$session" 2>/dev/null; then
          # Restore recreated "scratch": drop our placeholder.
          tmux kill-session -t "=$boot" 2>/dev/null || true
        else
          # First run (no save yet) or the save had no "scratch": the
          # placeholder simply becomes the scratch session.
          tmux rename-session -t "=$boot" "$session"
        fi
      fi

      exec tmux attach-session -t "=$session"
    '';
  };
in
{
  # Make the launcher the drop-down default. Priority 1200 sits strictly
  # between config.toml's [desktop].scratchpadCommand (mkDefault = 1000, so a
  # user override still wins) and the option's own `default`, which the module
  # system injects as a REAL definition at mkOptionDefault = 1500. (Using 1500
  # here collided with it: "conflicting definition values".)
  dynamic.desktop.scratchpad.command = lib.mkOverride 1200 (lib.getExe tmuxScratch);
  home.packages = [ tmuxScratch ];

  programs.tmux = {
    enable = true;
    terminal = "tmux-256color";
    historyLimit = 100000;
    shell = "${pkgs.zsh}/bin/zsh";
    mouse = true;
    # 50ms, not the more aggressive 10ms. This is how long tmux waits after an
    # ESC on its INPUT stream to decide "lone Esc key" vs "start of a sequence"
    # — and terminal query REPLIES (OSC 4/10/11 colour queries) arrive on that
    # same path as keystrokes. At 10ms a reply split across reads (exactly what
    # happens during a busy pane switch) timed out: tmux ate the ESC as a lone
    # Esc and injected the remainder as literal keys, which is where the stray
    # `rgb:d7d7/5f5f/8787` fragments (d7 / d7d7 / 5f5f — xterm 256-colour cube
    # levels in OSC reply encoding) came from. 50ms is still far below the
    # threshold where Esc feels laggy in vim. tmux's own default is 500.
    escapeTime = 50;
    prefix = "C-a";
    keyMode = "vi";

    # tmux-resurrect + tmux-continuum: persist the tmux environment (the "scratch"
    # session behind the drop-down terminal, plus any others) across reboots.
    # Saves land in ~/.local/share/tmux/resurrect/, which is on the persisted
    # /home (modules/persistence), so they survive a reboot. RESTORE is driven by
    # the `tmux-scratch` launcher above (restore-before-attach on a cold server),
    # NOT by continuum's racy at-server-start auto-restore. continuum is kept
    # only for its periodic autosave.
    plugins = with pkgs.tmuxPlugins; [
      {
        # FULL restore, like the original working config: pane CONTENTS
        # (scrollback) + programs are captured/replayed, and window properties
        # are restored — including custom window names. A manually renamed window
        # has automatic-rename=off, which resurrect saves and replays, so your
        # names survive (auto-named windows still follow their program). Processes
        # and automatic-rename are left at their defaults (on).
        #
        # The only reason this was ever turned off: resurrect's "Restoring…"
        # spinner (tmux_spinner.sh) is started at the top of restore.sh's main()
        # and only killed at the very end (`stop_spinner`). It spams
        # `tmux display-message` every 0.1s, so if any restore step stalls before
        # the end — as the heavier full restore did inside the ephemeral drop-down
        # — the spinner orphaned and flooded the status line forever.
        #
        # Fix (decoupled from the restore itself): kill the spinner the instant it
        # starts. main() runs the pre-restore-all hook immediately after
        # start_spinner, and SPINNER_PID is in scope there, so `kill -9
        # $SPINNER_PID` stops it before it can paint. Restore then runs silently;
        # the trailing stop_spinner just no-ops on the dead PID. Bar-flooding is
        # impossible regardless of how slow the full restore is — we no longer
        # depend on restore.sh reaching its own stop_spinner. (restore.sh has no
        # `set -e`.)
        plugin = resurrect;
        extraConfig = ''
          set -g @resurrect-capture-pane-contents 'on'
          set -g @resurrect-hook-pre-restore-all 'kill -9 $SPINNER_PID'
        '';
      }
      {
        # Keep continuum LAST: its autosave hook lives in status-right, so a later
        # plugin that overwrites status-right would silently disable it.
        plugin = continuum;
        extraConfig = ''
          # Auto-restore OFF on purpose: the tmux-scratch launcher restores
          # deterministically before attaching. Leaving this on would fire a
          # second, racing restore at server start (the old source of flakiness).
          set -g @continuum-restore 'off'
          set -g @continuum-save-interval '15'
        '';
      }
    ];

    extraConfig = ''
      set -g default-terminal "tmux-256color"
      set -ag terminal-overrides ",xterm-256color:RGB"

      # automatic-rename stays at the default (on). We do NOT force it off:
      # resurrect preserves custom window names on its own (a renamed window has
      # automatic-rename=off, which it saves and replays), while auto-named
      # windows keep following their restored program. Forcing it off globally
      # would also freeze new windows, which we don't want.

      set-window-option -g mode-keys vi

      unbind C-b
      unbind %
      unbind '"'
      unbind r
      unbind -T copy-mode-vi MouseDragEnd1Pane

      bind-key C-a send-prefix
      bind | split-window -h -c "#{pane_current_path}"
      bind - split-window -v -c "#{pane_current_path}"
      bind c new-window
      bind x kill-pane

      bind r source-file ~/.config/tmux/tmux.conf

      bind h select-pane -L
      bind j select-pane -D
      bind k select-pane -U
      bind l select-pane -R

      bind -r H resize-pane -L 5
      bind -r J resize-pane -D 5
      bind -r K resize-pane -U 5
      bind -r L resize-pane -R 5

      # Save the whole tmux environment whenever a client detaches — e.g. every
      # time the drop-down terminal is hidden. This runs resurrect's save script
      # directly, so it is independent of continuum's status-right autosave and
      # keeps working even after a live theme switch rewrites status-right.
      set-hook -g client-detached 'run-shell "${pkgs.tmuxPlugins.resurrect}/share/tmux-plugins/resurrect/scripts/save.sh"'
    '';
  };
}
