{ pkgs, ... }:
{
  programs.tmux = {
    enable = true;
    terminal = "tmux-256color";
    historyLimit = 100000;
    shell = "${pkgs.zsh}/bin/zsh";
    mouse = true;
    escapeTime = 10;
    prefix = "C-a";
    keyMode = "vi";

    # tmux-resurrect + tmux-continuum: persist the tmux environment (the "scratch"
    # session behind the drop-down terminal, plus any others) across reboots.
    # Saves land in ~/.local/share/tmux/resurrect/, which is on the persisted
    # /home (modules/persistence), so they survive a reboot; continuum restores
    # the last save the next time the tmux server starts — e.g. the first
    # drop-down open after boot (verified: `new-session -A -s scratch` restores
    # cleanly, no duplicate/empty session).
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
          set -g @continuum-restore 'on'
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
