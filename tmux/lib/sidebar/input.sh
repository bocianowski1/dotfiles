# shellcheck shell=bash
# shellcheck disable=SC2034,SC2154 # render's state, shared by the sidebar files (render.sh)
# Input: wait up to 2s (a minute when hidden) for keys and mouse reports, then act on them.
# `claude-sidebar refresh` wakes a sidebar early by typing C-r into its pane. Works on
# render's locals.

handle_input() {
  # Everything that arrived is handled token by token: mouse reports, arrow keys, Esc,
  # single keys. (-d '' so Enter arrives as a newline instead of ending the read.)
  # Mouse movement (hover) prefetches without a redraw, so moving over the sidebar stays cheap.
  local key k tok acted=0 waited_from=$SECONDS wait_for=2
  [ "$visible" = 1 ] || wait_for=60
  while [ "$acted" = 0 ] && [ $((SECONDS - waited_from)) -lt "$wait_for" ] &&
    IFS= read -rsn1 -d '' -t "$wait_for" key; do
    while IFS= read -rsn1 -d '' -t 0.01 k; do key+=$k; done
    while [ -n "$key" ]; do
      if [[ $key =~ ^$'\e'\[\<([0-9]+)\;[0-9]+\;([0-9]+)([Mm]) ]]; then
        # SGR mouse report: ESC [ < button ; column ; row M (press) or m (release)
        tok=${BASH_REMATCH[0]}
        [ "${BASH_REMATCH[1]}" = 35 ] || acted=1
        on_mouse "${BASH_REMATCH[1]}${BASH_REMATCH[3]}" "${BASH_REMATCH[2]}"
      elif [[ $key == $'\e'[[O][AB]* ]]; then
        acted=1
        tok=${key:0:3}
        if [ "$filter_typing" = 0 ] && [ "$nav" = 1 ]; then
          if [ "${tok:2}" = A ]; then nav_move -1; else nav_move 1; fi
        fi
      elif [[ $key == $'\e'* ]]; then
        acted=1
        tok=${key:0:1}
        on_escape
      else
        acted=1
        tok=${key:0:1}
        on_key "$tok"
      fi
      key=${key:${#tok}}
    done
  done
}

on_mouse() { # <button and M/m> <row>
  local at=$2
  case $1 in
  35M) # movement with no button held: hover
    local hovered=${click[$at]:-}
    if [[ $hovered == issue:* && $hovered != "$last_hover" ]]; then
      issue_prefetch "${hovered#issue:}"
    fi
    last_hover=$hovered
    ;;
  64M | 65M) # wheel: scroll the list under the mouse (elsewhere, nothing)
    local d=1
    [ "$1" = 64M ] && d=-1
    if [ "$at" -ge "$tree_top" ] && [ "$at" -le "$tree_bottom" ]; then
      tree_offset=$((tree_offset + d))
    elif [ "$at" -ge "$todo_top" ] && [ "$at" -le "$todo_bottom" ]; then
      todo_offset=$((todo_offset + d))
    elif [ "$at" -ge "$issue_top" ] && [ "$at" -le "$issue_bottom" ]; then
      issue_scroll "$d"
    fi
    ;;
  0M) activate "${click[$at]:-}" ;;
  esac
}

on_escape() {
  if [ "$filter_typing" = 1 ]; then
    filter_typing=0 issue_filter='' issue_offset=0 issue_sel=0
  elif [ -n "$issue_filter" ]; then
    # A filter is applied: Esc clears it first (keeping the selected issue selected,
    # now in the whole list); the next Esc leaves keyboard mode
    issue_filter=''
    load_issue_rows
    if [ "$nav" = 1 ] && [[ $nav_target == issue:* ]]; then
      local at
      at=$(issue_index_of "${nav_target#issue:}")
      nav_select_issue "${at:-0}"
    else
      issue_offset=0 issue_sel=0
    fi
  elif [ "$nav" = 1 ]; then
    nav_exit
  fi
}

on_key() { # <one character>
  case $1 in
  $'\x12') # redraw request (claude-sidebar refresh); the issue popup also uses it
    # to say which issue it shows, which gets selected and scrolled into view
    local shown at
    shown=$(tmux show -gv @claude_issue_selected 2>/dev/null)
    if [ -n "$shown" ] && [ "$shown" != "$followed_issue" ]; then
      followed_issue=$shown
      at=$(issue_index_of "$shown")
      if [ -n "$at" ]; then
        issue_sel=$at
        issue_move 0
        [ "$nav" = 1 ] && nav_target="issue:$shown"
      fi
    fi
    ;;
  $'\x14') # prefix i (claude-sidebar focus issues): keyboard into the issue list
    nav=1
    [ "$issue_sel" -ge "$issue_offset" ] && [ "$issue_sel" -lt $((issue_offset + issue_rows_vis)) ] || issue_sel=$issue_offset
    [ "$issue_total" -gt 0 ] && nav_select_issue "$issue_sel"
    ;;
  $'\x05') # prefix e (claude-sidebar focus): keyboard into the sidebar, starting on the
    # pane you came from if it is a Claude session, else its window
    nav=1
    local came_from r
    came_from=$(tmux list-panes -t "$TMUX_PANE" -F '#{pane_last} #{pane_id}' | awk '$1 == 1 { print $2 }')
    nav_target=$window_id
    for r in "${!click[@]}"; do [ "${click[$r]}" = "$came_from" ] && nav_target=$came_from; done
    ;;
  *)
    if [ "$filter_typing" = 1 ]; then
      # Typing a filter: every printable key goes into it
      case $1 in
      $'\n' | $'\r')
        filter_typing=0
        [ "$nav" = 1 ] && [ "$issue_total" -gt 0 ] && nav_select_issue 0
        ;;
      $'\x7f' | $'\b') issue_filter=${issue_filter%?} issue_offset=0 issue_sel=0 ;;
      [[:print:]]) issue_filter+=$1 issue_offset=0 issue_sel=0 ;;
      esac
      return
    fi
    case $1 in
    /) filter_typing=1 ;;
    t) [ "$nav" = 1 ] && minutes_cycle "$ISSUE_TTL_FILE" ;;
    n) [ "$nav" = 1 ] && issue_new ;;
    j) [ "$nav" = 1 ] && nav_move 1 ;;
    k) [ "$nav" = 1 ] && nav_move -1 ;;
    g) [ "$nav" = 1 ] && nav_edge first ;;
    G) [ "$nav" = 1 ] && nav_edge last ;;
    $'\n' | $'\r') [ "$nav" = 1 ] && activate "$nav_target" ;;
    q)
      if [ "$nav" = 1 ]; then
        nav_exit
      else
        off
        exit 0
      fi
      ;;
    a) todo_prompt ;;
    e) todo_edit ;;
    R)
      calendar_fetch force
      issues_fetch force
      ;;
    esac
    ;;
  esac
}
