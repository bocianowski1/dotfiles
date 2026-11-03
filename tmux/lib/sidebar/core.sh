# shellcheck shell=bash
# The sidebar panes themselves (one per window, on the left), and small shared helpers.
# shellcheck disable=SC2034 # (the other sidebar files use these)
WIDTH=34
US=$'\x1f' # field separator: not whitespace, so empty fields survive read
# What the window tree reads of each pane, one line per pane (see tree_build)
FMT="#{window_id}${US}#{pane_id}${US}#{window_index}${US}#{window_name}${US}#{window_active}${US}#{pane_active}${US}#{@claude_state}${US}#{pane_title}${US}#{pane_current_path}${US}#{pane_current_command}${US}#{@claude_sidebar}${US}#{@last_opened}${US}#{@claude_marked}${US}#{@claude_replied}${US}#{@claude_issue}"

sidebar_panes() {
  tmux list-panes -a -F '#{pane_id} #{@claude_sidebar}' | awk '$2 == "1" { print $1 }'
}

sidebars_on() { [ "$(tmux show -gv @claude_sidebar_on 2>/dev/null)" = 1 ]; }

add() { # <window>: give it a sidebar
  local window=$1
  # The issue image viewer gets the whole window
  [ "$(tmux display -p -t "$window" '#{window_name}')" = issue-image ] && return
  tmux list-panes -t "$window" -F '#{@claude_sidebar}' | grep -qx 1 && return
  tmux split-window -d -f -h -b -l "$WIDTH" -t "$window" "'$self' render"
}

on() {
  tmux set -g @claude_sidebar_on 1
  tmux set -g status off
  local w
  for w in $(tmux list-windows -a -F '#{window_id}'); do add "$w"; done
}

off() {
  tmux set -gu @claude_sidebar_on
  tmux set -g status on
  # When run from inside a sidebar (the q key), close that pane last
  local p
  for p in $(sidebar_panes); do [ "$p" = "${TMUX_PANE:-}" ] || tmux kill-pane -t "$p"; done
  sidebar_panes | grep -qx "${TMUX_PANE:-none}" && tmux kill-pane -t "$TMUX_PANE"
}

# Redraw every sidebar but <pane> (that one redraws itself): one tmux call for them all.
# The redraw request is C-r (\x12), not a letter: no clash with typing.
refresh_others() { # [pane]
  local p args=()
  for p in $(sidebar_panes); do
    [ "$p" = "${1:-}" ] || args+=(send-keys -t "$p" C-r \;)
  done
  [ ${#args[@]} -gt 0 ] && tmux "${args[@]:0:${#args[@]}-1}"
}

# Toggle a window's mark (green in the tree): a visual tag for the projects you are
# switching between
mark() { # <window>
  if [ "$(tmux show -wv -t "$1" @claude_marked 2>/dev/null)" = 1 ]; then
    tmux set -wu -t "$1" @claude_marked
  else
    tmux set -w -t "$1" @claude_marked 1
  fi
}

# Focus <window> on the pane you were using there, never its sidebar
focus_window() {
  local pane
  pane=$(tmux list-panes -t "$1" -F '#{pane_active} #{pane_last} #{pane_id} #{@claude_sidebar}' |
    awk '$4 != "1" { score = $1 * 2 + $2; if (!found || score > best) { best = score; id = $3; found = 1 } }
         END { print id }')
  [ -n "$pane" ] && tmux switch-client -t "$pane"
}

# Keyboard into the current window's sidebar (prefix e), or straight into its issues
# (prefix i): selects the sidebar pane and tells it which, by C-e or C-t
focus_sidebar() { # [issues]
  sidebars_on || on
  local win sb= i
  win=$(tmux display -p '#{window_id}')
  # A sidebar that was just opened needs a moment to mark itself
  for i in $(seq 20); do
    sb=$(tmux list-panes -t "$win" -F '#{pane_id} #{@claude_sidebar}' | awk '$2 == "1" { print $1 }')
    [ -n "$sb" ] && break
    sleep 0.1
  done
  [ -n "$sb" ] || return 0
  tmux select-pane -t "$sb"
  if [ "${1:-}" = issues ]; then tmux send-keys -t "$sb" C-t; else tmux send-keys -t "$sb" C-e; fi
}

# "↑2 ↓5" into more: how many rows a scrolled list hides above and below (empty when none)
scroll_marks() { # <above> <below>
  more=
  [ "$1" -gt 0 ] && more="↑$1"
  [ "$2" -gt 0 ] && more+="${more:+ }↓$2"
  return 0
}
