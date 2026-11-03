# shellcheck shell=bash
# Clicks and keyboard mode (prefix e, prefix i). These work on render's locals. A row's
# click target is a string: "@window", "%pane", "issue:<url>", "todo:<line>", "todo-edit",
# "ttl", "recent" or "filter". In keyboard mode the selection, nav_target, is one of them,
# so Enter does exactly what a click on that row does; nav_order lists them top to bottom.

# What a click (or Enter in keyboard mode) on a row does
activate() { # <click target>
  case $1 in
  @*) focus_window "$1" ;;
  %*) tmux switch-client -t "$1" ;;
  issue:*) issue_open "${1#issue:}" ;;
  todo:*)
    # Optimistic: tick it off here and redraw at once; the other sidebars follow behind
    todo_tick "${1#todo:}"
    "$self" refresh-others "$TMUX_PANE" </dev/null >/dev/null 2>&1 &
    ;;
  todo-edit) todo_edit ;;
  ttl) minutes_cycle "$ISSUE_TTL_FILE" ;;
  recent) minutes_cycle "$RECENT_FILE" ;;
  filter) filter_typing=1 ;;
  esac
}

nav_select_issue() { # <index>: select that issue (scrolled into view, prefetched)
  issue_sel=$1
  issue_move 0
  issue_url_at "$issue_sel"
  nav_target="issue:$issue_url"
}

nav_move() { # <1|-1>: the next/previous row you can act on
  local d=$1 i at=-1
  # Within the issues, step through the whole (filtered) list, scrolling as needed
  if [[ $nav_target == issue:* ]] && [ $((issue_sel + d)) -ge 0 ] && [ $((issue_sel + d)) -lt "$issue_total" ]; then
    nav_select_issue $((issue_sel + d))
    return
  fi
  for i in "${!nav_order[@]}"; do [ "${nav_order[i]}" = "$nav_target" ] && at=$i; done
  if [ "$at" -lt 0 ]; then
    nav_target=${nav_order[0]:-}
    return
  fi
  i=$((at + d))
  [ "$i" -ge 0 ] && [ "$i" -lt ${#nav_order[@]} ] || return
  nav_target=${nav_order[i]}
  if [[ $nav_target == issue:* ]]; then
    # Coming into the issues from below lands on the last one, from above on the first
    if [ "$d" -lt 0 ]; then nav_select_issue $((issue_total - 1)); else nav_select_issue 0; fi
  fi
}

nav_edge() { # <first|last>
  if [[ $nav_target == issue:* ]]; then
    if [ "$1" = first ]; then nav_select_issue 0; else nav_select_issue $((issue_total - 1)); fi
  elif [ ${#nav_order[@]} -gt 0 ]; then
    if [ "$1" = first ]; then nav_target=${nav_order[0]}; else nav_target=${nav_order[${#nav_order[@]} - 1]}; fi
  fi
}

nav_exit() { # back to the pane you came from
  nav=0
  tmux last-pane -t "$TMUX_PANE" 2>/dev/null || focus_window "$(tmux display -p -t "$TMUX_PANE" '#{window_id}')"
}
