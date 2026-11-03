# Helpers for the tmux sidebar tests (sourced by run). Each test gets its own tmux server
# and its own HOME, so nothing touches your real tmux, todos, calendar or GitHub:
#   start_tmux <cols> <rows>     a detached server with one session ("main")
#   add_window [name]            another window; prints its id
#   add_session <window> <title> [state] [replied epoch] [issue url]
#                                a pane that looks like a Claude session; prints its id
#   start_sidebars [width]       a sidebar in every window, waiting until it has drawn
#   screen / screen_raw          the active window's sidebar, as text / with colour codes
#   wait_for <regex> [s]         poll the screen until it matches (fails after s seconds)
#   click / wheel / keys         mouse and keyboard input into the sidebar
#   assert_eq / assert_match / assert_no_match / fail
# Fixtures: todos <n>, issues <n>, meetings <rows...>, setting <name> <minutes>
TEST_DIR=$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)
BIN=$(cd "$TEST_DIR/../bin" && pwd)
LIB=$(cd "$TEST_DIR/../lib" 2>/dev/null && pwd)
ESC=$'\e'

setup() {
  T_HOME=$(mktemp -d "${TMPDIR:-/tmp}/sidebar-test.XXXXXX")
  SOCK="sidebar-test-$$-$RANDOM"
  # A gh that always fails: the sidebar shows issues when gh exists, but must never call it
  mkdir -p "$T_HOME/bin" "$T_HOME/.config/claude-sidebar" "$T_HOME/.cache/claude-sidebar"
  printf '#!/bin/sh\nexit 1\n' >"$T_HOME/bin/gh"
  chmod +x "$T_HOME/bin/gh"
  export HOME=$T_HOME PATH="$T_HOME/bin:$PATH" CLAUDE_SIDEBAR_NO_FETCH=1 CLAUDE_SIDEBAR_GH_TOKEN=test
  unset TMUX TMUX_PANE
}

teardown() {
  tm kill-server 2>/dev/null
  rm -rf "$T_HOME"
}

tm() { tmux -L "$SOCK" "$@"; }

start_tmux() { # <cols> <rows>
  tm -f /dev/null new-session -d -s main -x "$1" -y "$2" "sleep 1d"
  # Scripts the test runs itself (hooks, claude-sessions) talk to this server too
  export TMUX="$(tm display -p '#{socket_path}'),0,0"
}

add_window() { # [name]
  tm new-window -d -P -F '#{window_id}' -t main -n "${1:-work}" "sleep 1d"
}

first_window() { tm list-windows -t main -F '#{window_id}' | head -1; }

add_session() { # <window> <title> [state] [replied epoch] [issue url]
  local pane
  pane=$(tm split-window -d -P -F '#{pane_id}' -t "$1" "sleep 1d")
  tm select-pane -t "$pane" -T "$2"
  tm set -p -t "$pane" @claude_state "${3:-idle}"
  [ -z "${4:-}" ] || tm set -p -t "$pane" @claude_replied "$4"
  [ -z "${5:-}" ] || tm set -p -t "$pane" @claude_issue "$5"
  echo "$pane"
}

start_sidebars() { # [width]
  local w
  for w in $(tm list-windows -t main -F '#{window_id}'); do
    tm split-window -d -f -h -b -l "${1:-34}" -t "$w" "'$BIN/claude-sidebar' render"
  done
  wait_for 'Todo'
}

sidebar() { # the sidebar pane of the active window
  tm list-panes -t main -F '#{pane_id} #{@claude_sidebar}' | awk '$2 == 1 { print $1; exit }'
}

screen() { tm capture-pane -p -t "$(sidebar)" | sed 's/ *$//'; }
screen_raw() { tm capture-pane -p -e -t "$(sidebar)"; }
line() { screen | sed -n "${1}p"; }                  # <row>
row_of() { screen | grep -n -m1 -E -- "$1" | cut -d: -f1; } # <regex>: its first row

wait_for() { # <regex> [seconds]
  local until=$((SECONDS + ${2:-3}))
  while [ "$SECONDS" -le "$until" ]; do
    screen | grep -q -E -- "$1" && return 0
    sleep 0.05
  done
  fail "screen never matched /$1/:"$'\n'"$(screen)"
}
wait_gone() { # <regex> [seconds]
  local until=$((SECONDS + ${2:-3}))
  while [ "$SECONDS" -le "$until" ]; do
    screen | grep -q -E -- "$1" || return 0
    sleep 0.05
  done
  fail "screen still matches /$1/:"$'\n'"$(screen)"
}

# SGR mouse reports, as the terminal sends them
click() { tm send-keys -t "$(sidebar)" -l "$ESC[<0;5;${1}M$ESC[<0;5;${1}m"; } # <row>
wheel() { # <up|down> <row>
  local b=65
  [ "$1" = up ] && b=64
  tm send-keys -t "$(sidebar)" -l "$ESC[<$b;5;${2}M"
}
keys() { tm send-keys -t "$(sidebar)" "$@"; }

todos() { # <n>: todo 1 .. todo n, all open
  local i
  for ((i = 1; i <= $1; i++)); do printf -- '- [ ] todo %s\n' "$i"; done >"$HOME/.config/claude-sidebar/todo.md"
}
issues() { # <n>: owner/repo#1 .. #n, the first one assigned to you
  local i
  for ((i = 1; i <= $1; i++)); do
    printf 'repo\t%s\t%s\tissue %s\thttps://github.com/owner/repo/issues/%s\n' "$i" $((i == 1)) "$i" "$i"
  done >"$HOME/.cache/claude-sidebar/issues.tsv"
}
meetings() { # <"start-epoch title">...: the calendar cache (and a calendar to have one)
  local m
  echo "https://calendar.invalid/x.ics" >"$HOME/.config/claude-sidebar/calendar-url"
  for m in "$@"; do printf '%s\t%s\t%s\t\n' "${m%% *}" $((${m%% *} + 1800)) "${m#* }"; done >"$HOME/.cache/claude-sidebar/calendar.tsv"
}
setting() { echo "$2" >"$HOME/.config/claude-sidebar/$1"; } # <recent-minutes|issue-ttl> <n>

fail() {
  echo "FAIL: $*" >&2
  exit 1
}
assert_eq() { # <expected> <actual> [what]
  [ "$1" = "$2" ] || fail "${3:-value}: expected [$1], got [$2]"
}
assert_match() { # <regex> <text> [what]
  [[ $2 =~ $1 ]] || fail "${3:-text} does not match /$1/:"$'\n'"$2"
}
assert_no_match() { # <regex> <text> [what]
  [[ ! $2 =~ $1 ]] || fail "${3:-text} matches /$1/:"$'\n'"$2"
}
