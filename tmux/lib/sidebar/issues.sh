# shellcheck shell=bash
# shellcheck disable=SC2034,SC2154 # render's state, shared by the sidebar files (render.sh)
# The issue block: your open GitHub issues (claude-issues fetches them into ISSUES_CACHE),
# a scrolled window of them, and the issue popup (claude-issue) they open.
ISSUES_CACHE=$CACHE_DIR/issues.tsv
ISSUES_ROWS=8               # issues visible at most; the mouse wheel scrolls through the rest
issue_rows_vis=$ISSUES_ROWS # fewer on a short pane (compose_frame works it out every frame)

# The issues to show, into issue_rows (cache rows) and issue_total: all of claude-issues'
# cache, or those matching issue_filter (case-insensitive, on repo#number and title)
load_issue_rows() {
  issue_rows=()
  if [ ! -f "$ISSUES_CACHE" ]; then
    issue_total=0
    return
  fi
  if [ -z "$issue_filter" ]; then
    mapfile -t issue_rows <"$ISSUES_CACHE"
  else
    local row repo num mine title url
    while IFS= read -r row; do
      IFS=$'\t' read -r repo num mine title url <<<"$row"
      [[ "${repo,,}#$num ${title,,}" == *"${issue_filter,,}"* ]] && issue_rows+=("$row")
    done <"$ISSUES_CACHE"
  fi
  issue_total=${#issue_rows[@]}
  [ "$issue_sel" -lt "$issue_total" ] || issue_sel=$((issue_total > 0 ? issue_total - 1 : 0))
  local last=$((issue_total - issue_rows_vis))
  [ "$last" -ge 0 ] || last=0
  [ "$issue_offset" -le "$last" ] || issue_offset=$last
}

# The url of issue_rows[<index>] into issue_url
issue_url_at() { # <index>
  local f
  IFS=$'\t' read -r f f f f issue_url <<<"${issue_rows[$1]:-}"
}

# The index of <url> in issue_rows, or nothing
issue_index_of() { # <url>
  local i
  for i in "${!issue_rows[@]}"; do
    if [[ ${issue_rows[i]} == *$'\t'"$1" ]]; then
      echo "$i"
      return
    fi
  done
}

# The visible window of issue_rows into issue_lines / issue_urls, from issue_offset; with a
# filter line under the header while you type one (or one is set). ◆ marks issues a Claude
# session works on (issue_session).
issue_lines() { # <width>
  local width=$1 ESC=$'\e'
  local RESET="${ESC}[0m" BOLD="${ESC}[1m" DIM="${ESC}[38;5;245m" MINE="${ESC}[38;5;214m" KEYC="${ESC}[38;5;215m"
  local offset=$issue_offset
  issue_lines=() issue_urls=()
  command -v gh >/dev/null || return
  local range=''
  [ "$issue_total" -gt "$issue_rows_vis" ] && range="$((offset + 1))–$((offset + issue_rows_vis > issue_total ? issue_total : offset + issue_rows_vis)) of $issue_total ↕"
  [ "$issue_total" -gt 0 ] && [ -z "$range" ] && range="$issue_total open"
  [ -n "$issue_filter" ] && [ "$issue_total" -le "$issue_rows_vis" ] && range="$issue_total match"
  local head
  printf -v head '%s Issues%s%*s%s' "$BOLD" "$RESET$DIM" $((width - 8)) "$range" "$RESET"
  issue_lines+=("$head") issue_urls+=("")
  if [ "$filter_typing" = 1 ] || [ -n "$issue_filter" ]; then
    local cursor=''
    [ "$filter_typing" = 1 ] && cursor="${KEYC}▏${RESET}"
    issue_lines+=("  ${KEYC}/${RESET} ${issue_filter}${cursor}") issue_urls+=(filter)
  fi
  if [ "$issue_total" = 0 ]; then
    if [ -n "$issue_filter" ]; then issue_lines+=("${DIM}  No issue matches${RESET}"); else issue_lines+=("${DIM}  No open issues${RESET}"); fi
    issue_urls+=("")
    return
  fi

  local i repo num mine title url ref max dot has
  for ((i = offset; i < offset + issue_rows_vis && i < issue_total; i++)); do
    IFS=$'\t' read -r repo num mine title url <<<"${issue_rows[i]}"
    [ ${#repo} -gt 12 ] && repo="${repo:0:11}…"
    ref="$repo#$num"
    max=$((width - ${#ref} - 5))
    [ ${#title} -gt "$max" ] && title="${title:0:max-1}…"
    dot=' ' has=' '
    [ "$mine" = 1 ] && dot="${MINE}●${RESET}"
    [ -n "${issue_session[$url]:-}" ] && has="${ESC}[38;5;110m◆${RESET}"
    issue_lines+=(" $has$dot ${DIM}${ref}${RESET} $title") issue_urls+=("$url")
  done
  local minutes
  minutes_setting "$ISSUE_TTL_FILE"
  issue_lines+=("${DIM}  cache ${minutes}m · click to change${RESET}") issue_urls+=(ttl)
}

# Refresh the issues cache in the background every 5 minutes, or now with "force"
# (one fetch at a time); the sidebars redraw as soon as it lands
# (CLAUDE_SIDEBAR_NO_FETCH=1, as in the tests: never)
issues_fetch() { # [force]
  [ -z "${CLAUDE_SIDEBAR_NO_FETCH:-}" ] || return 0
  command -v gh >/dev/null || return
  local age=999999
  [ -f "$ISSUES_CACHE" ] && age=$((EPOCHSECONDS - $(stat -c %Y "$ISSUES_CACHE")))
  [ "${1:-}" = force ] || [ "$age" -ge 300 ] || return
  mkdir -p "${ISSUES_CACHE%/*}"
  { flock -n "${ISSUES_CACHE%/*}/issues.lock" "${self%/*}/claude-issues" && "$self" refresh; } </dev/null >/dev/null 2>&1 &
}

# Back from the browser after opening an issue from the sidebar (the focus-in hook): refetch
# now and again 30s later, since GitHub's search can take a little while to see a change
issues_refetch_after_browser() {
  [ "$(tmux show -gv @claude_issues_dirty 2>/dev/null)" = 1 ] || return 0
  tmux set -gu @claude_issues_dirty
  issues_fetch force
  (sleep 30 && issues_fetch force) >/dev/null 2>&1 &
}

issue_scroll() { # <rows>; keeps a selected issue inside the visible window
  local last=$((issue_total - issue_rows_vis))
  [ "$last" -ge 0 ] || last=0
  issue_offset=$((issue_offset + $1))
  [ "$issue_offset" -le "$last" ] || issue_offset=$last
  [ "$issue_offset" -ge 0 ] || issue_offset=0
  if [ "$nav" = 1 ] && [[ $nav_target == issue:* ]]; then
    [ "$issue_sel" -ge "$issue_offset" ] || issue_sel=$issue_offset
    [ "$issue_sel" -lt $((issue_offset + issue_rows_vis)) ] || issue_sel=$((issue_offset + issue_rows_vis - 1))
    issue_url_at "$issue_sel"
    nav_target="issue:$issue_url"
  fi
}
issue_move() { # <issues>; scrolls to keep the selection visible, prefetches the selection
  [ "$issue_total" -gt 0 ] || return
  issue_sel=$((issue_sel + $1))
  [ "$issue_sel" -lt "$issue_total" ] || issue_sel=$((issue_total - 1))
  [ "$issue_sel" -ge 0 ] || issue_sel=0
  [ "$issue_sel" -ge "$issue_offset" ] || issue_offset=$issue_sel
  [ "$issue_sel" -lt $((issue_offset + issue_rows_vis)) ] || issue_offset=$((issue_sel - issue_rows_vis + 1))
  issue_url_at "$issue_sel"
  issue_prefetch "$issue_url"
}

issue_new() { # the "new issue" popup (claude-issue new)
  local window
  window=$(tmux display -p -t "$TMUX_PANE" '#{window_id}')
  tmux display-popup -E -w 70% -h 70% -T " New issue " "'${self%/*}/claude-issue' new '$window'" </dev/null >/dev/null 2>&1 &
}
issue_open() { # <url>: the issue view popup (claude-issue), over the window this sidebar is in
  "${self%/*}/claude-issue" open "$1" "$(tmux display -p -t "$TMUX_PANE" '#{window_id}')" </dev/null >/dev/null 2>&1 &
}
# Fetch an issue for the popup in the background, at the text width the popup will have
# (85% of the window, minus borders and margin), so opening it is instant
issue_prefetch() { # <url>
  [ -n "$1" ] || return
  "${self%/*}/claude-issue" prefetch "$1" $((window_width * 85 / 100 - 4)) </dev/null >/dev/null 2>&1 &
}
