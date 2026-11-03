# shellcheck shell=bash
# Shared by the claude-* tmux scripts (sourced): where settings and caches live, the
# minutes settings, and the GitHub token.
# shellcheck disable=SC2034 # (the scripts that source this use these)
CONFIG_DIR=~/.config/claude-sidebar
CACHE_DIR=${CLAUDE_SIDEBAR_CACHE:-~/.cache/claude-sidebar} # CLAUDE_SIDEBAR_CACHE: tests
# Issues are always this login's, whichever gh account is active
GH_USER=torgermalling

# Settings in minutes, each a number in its own file; a click in the sidebar cycles them
ISSUE_TTL_FILE=$CONFIG_DIR/issue-ttl   # how long a fetched issue is cached (claude-issue)
RECENT_FILE=$CONFIG_DIR/recent-minutes # how long a session that answered stays orange
MINUTE_STEPS=(5 15 30 60)              # the values a click cycles through

# A minutes setting: its file's number, or 15 (no subshell: the sidebar reads these on
# every redraw)
minutes_setting() { # <file> → minutes
  minutes=15
  [ -f "$1" ] && read -r minutes <"$1"
  [[ $minutes =~ ^[0-9]+$ ]] || minutes=15
}
minutes_cycle() { # <file>: on to the next of MINUTE_STEPS (after the last: the first)
  local minutes next=${MINUTE_STEPS[0]} i
  minutes_setting "$1"
  for i in "${MINUTE_STEPS[@]}"; do
    if [ "$i" -gt "$minutes" ]; then
      next=$i
      break
    fi
  done
  mkdir -p "${1%/*}"
  echo "$next" >"$1"
}

# The GH_USER token into GH_TOKEN, asked of gh once per process tree: whoever starts a
# script (the sidebar, a popup) passes it on in CLAUDE_SIDEBAR_GH_TOKEN, only in memory
gh_token() {
  if [ -z "${CLAUDE_SIDEBAR_GH_TOKEN:-}" ] && command -v gh >/dev/null; then
    CLAUDE_SIDEBAR_GH_TOKEN=$(gh auth token --user "$GH_USER" 2>/dev/null)
  fi
  export CLAUDE_SIDEBAR_GH_TOKEN=${CLAUDE_SIDEBAR_GH_TOKEN:-}
  export GH_TOKEN=$CLAUDE_SIDEBAR_GH_TOKEN
}
