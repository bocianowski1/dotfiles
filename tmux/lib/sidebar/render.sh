# shellcheck shell=bash
# shellcheck disable=SC2034,SC2154 # render's state, shared by the sidebar files (render.sh)
# The draw loop running inside each sidebar pane: read the state from tmux, draw a frame
# (only the sidebar you can see), wait for input or a redraw request, repeat.
# render's locals are the sidebar's state; the other sidebar files work on them.

render() {
  # Mark this pane (also after a tmux-resurrect restore, which starts us without the option)
  tmux set -p -t "$TMUX_PANE" @claude_sidebar 1
  tmux set -g @claude_sidebar_on 1
  tmux set -g status off

  local ESC=$'\e'
  gh_token # once; the issue jobs this sidebar starts reuse it
  local host continuum last_continuum=0
  host=$(hostname)
  continuum=~/.tmux/plugins/tmux-continuum/scripts/continuum_save.sh
  # Hide the cursor; ask for SGR mouse reports of clicks and of movement (for hover prefetch)
  trap 'printf "%s" "${ESC}[?1003l${ESC}[?1000l${ESC}[?1006l${ESC}[?25h${ESC}[?7h"; stty echo 2>/dev/null' EXIT
  # Echo off for good, not just while read waits: mouse movement arriving while the sidebar
  # is busy (e.g. starting a prefetch) was otherwise echoed as ^[[<35;… after the footer
  stty -echo 2>/dev/null
  # (no screen clear: every frame overwrites each line and clears below, and a clear here
  # flashed all sidebars whenever they restarted, e.g. on a script change)
  # Autowrap off: a line too long for the pane is cut instead of wrapping onto another row,
  # which pushed the top of the frame out of the pane
  printf '%s' "${ESC}[?25l${ESC}[?7l${ESC}[?1000h${ESC}[?1003h${ESC}[?1006h"

  local -A click=()         # screen row → click target (see nav.sh)
  local -A issue_session=() # issue url → 1 when a Claude session works on it
  local -a cal_lines cal_urls todo_lines todo_refs todo_all todo_all_refs issue_lines issue_urls issue_rows nav_order tree_panes
  local width height panes visible focused window_width window_id
  local issue_offset=0 issue_total=0 issue_sel=0 issue_filter='' filter_typing=0 last_hover='' followed_issue
  local nav=0 nav_target='' nav_seen='' issue_url='' checked_at=-99 last_frame=''
  local tree_offset=0 tree_top=0 tree_bottom=0 todo_offset=0 todo_top=0 todo_bottom=0 issue_top=0 issue_bottom=-1
  # Only follow issues the popup moves to from now on, not one it showed before we started
  followed_issue=$(tmux show -gv @claude_issue_selected 2>/dev/null)

  local version
  version=$(code_version)
  while true; do
    # Every 2s at most (not on every key press): the code was edited → restart on the new
    # code (keeps the pane and its options)
    if [ $((SECONDS - checked_at)) -ge 2 ] && [ "$(code_version)" != "$version" ]; then
      exec "$self" render
    fi
    read_state
    # tmux resizes panes in proportion when a window changes size: put the sidebar back
    if [ "$visible" = 1 ] && [ "$width" != "$WIDTH" ] && [ "${window_width:-0}" -ge $((WIDTH * 2)) ]; then
      tmux resize-pane -t "$TMUX_PANE" -x "$WIDTH" && width=$WIDTH
    fi
    # Keyboard mode (and typing a filter) ends when you click or move away from the sidebar
    [ "$focused" = 1 ] || nav=0 filter_typing=0
    load_issue_rows
    # Only the sidebar is left in this window: close the window
    if [ "$panes" = 1 ]; then
      tmux kill-window -t "$TMUX_PANE"
      exit 0
    fi

    # Only the sidebar you can see draws; hidden ones wait (up to a minute) and are woken by
    # the window-switch hook the moment their window comes into view
    [ "$visible" = 1 ] && compose_frame

    # The status bar normally drives tmux-continuum's autosave; with it hidden, the
    # visible sidebar does (continuum itself still only saves every @continuum-save-interval)
    if [ "$visible" = 1 ] && [ $((SECONDS - last_continuum)) -ge 60 ] && [ -x "$continuum" ]; then
      "$continuum" </dev/null >/dev/null 2>&1 &
      last_continuum=$SECONDS
    fi
    # Whether the calendar or issues are due a refetch: checked every 2s, not on every key
    if [ $((SECONDS - checked_at)) -ge 2 ]; then
      if [ "$visible" = 1 ]; then
        calendar_fetch
        issues_fetch
      fi
      checked_at=$SECONDS
    fi

    handle_input
  done
}

# When any of the sidebar's code last changed (the script and its lib files)
code_version() { stat -c %Y "$self" "$LIB"/common.sh "$LIB"/sidebar/*.sh | tr '\n' ' '; }

# This pane's size and state, the session's panes (for the tree) and, from every session,
# the issues Claude sessions work on (lines starting with "I"): one tmux call
read_state() {
  local -a tmux_out
  local l
  mapfile -t tmux_out < <(tmux display -p -t "$TMUX_PANE" '#{pane_width} #{pane_height} #{window_panes} #{window_active} #{pane_active} #{window_width} #{window_id}' \; list-panes -s -t "$TMUX_PANE" -F "$FMT" \; list-panes -a -F 'I#{?#{&&:#{@claude_state},#{@claude_issue}},#{@claude_issue},}')
  read -r width height panes visible focused window_width window_id <<<"${tmux_out[0]:-}"
  issue_session=() tree_panes=()
  for l in "${tmux_out[@]:1}"; do
    case $l in
    I) ;;
    I*) issue_session[${l#I}]=1 ;;
    *) tree_panes+=("$l") ;;
    esac
  done
}

# One frame: the window tree at the top, then pinned above the footer the todo, calendar
# and issue blocks, separated by lines. Sets click (screen row → target), the row ranges
# the mouse wheel scrolls, and nav_order.
compose_frame() {
  local RESET="${ESC}[0m" DIM="${ESC}[38;5;245m"
  local out row i minutes recent_minutes
  local -a tree_text tree_click
  minutes_setting "$RECENT_FILE"
  recent_minutes=$minutes
  click=()
  tree_build

  # The bottom block, as (text, click target) pairs first so the room above it is known
  local now rule
  printf -v now '%(%s)T' -1
  printf -v rule '%*s' $((width - 2)) ''
  rule=" ${DIM}${rule// /─}${RESET}"
  local -a b_text=() b_click=() b_nav=()
  todo_lines "$width"
  local b_todo_end=${#todo_lines[@]} # todo rows are b_text[0 .. b_todo_end-1]
  b_nav+=(todo-edit)
  for i in "${todo_all_refs[@]}"; do b_nav+=("todo:$i"); done
  for i in "${!todo_lines[@]}"; do
    b_text+=("${todo_lines[i]}")
    case ${todo_refs[i]} in
    edit) b_click+=(todo-edit) ;;
    [0-9]*) b_click+=("todo:${todo_refs[i]}") ;;
    *) b_click+=("") ;;
    esac
  done
  calendar_lines "$width" "$now"
  if [ ${#cal_lines[@]} -gt 0 ]; then
    b_text+=("" "$rule" "") b_click+=("" "" "")
    # No click action on meetings: explorer.exe opened the Documents folder for Teams
    # links, and new Outlook has no documented link straight to its calendar
    for i in "${!cal_lines[@]}"; do b_text+=("${cal_lines[i]}") b_click+=(""); done
  fi
  # On a short pane the issues give up rows first, so the tree keeps at least 3 (block:
  # rule and blank lines, header, a filter line, the issues, the cache line)
  local tree_want=${#tree_text[@]} filter_row=0
  [ "$tree_want" -le 3 ] || tree_want=3
  if [ "$filter_typing" = 1 ] || [ -n "$issue_filter" ]; then filter_row=1; fi
  issue_rows_vis=$((height - 2 - ${#b_text[@]} - 3 - 1 - filter_row - 1 - 2 - 1 - tree_want))
  [ "$issue_rows_vis" -le "$ISSUES_ROWS" ] || issue_rows_vis=$ISSUES_ROWS
  [ "$issue_rows_vis" -ge 1 ] || issue_rows_vis=1
  issue_scroll 0
  issue_lines "$width"
  local b_issue_start=-1 # issue rows are b_text[b_issue_start ..] (to the end)
  if [ ${#issue_lines[@]} -gt 0 ]; then
    b_text+=("" "$rule" "") b_click+=("" "" "")
    b_issue_start=${#b_text[@]}
    for i in "${!issue_lines[@]}"; do
      b_text+=("${issue_lines[i]}")
      case ${issue_urls[i]} in
      ttl | filter) b_click+=("${issue_urls[i]}") ;;
      '') b_click+=("") ;;
      *) b_click+=("issue:${issue_urls[i]}") ;;
      esac
      [ -n "${b_click[-1]}" ] && [ "${b_click[-1]}" != filter ] && b_nav+=("${b_click[-1]}")
    done
  fi

  # The tree gets the rows the bottom block, header and footer leave (and a blank line)
  tree_draw $((height - 2 - ${#b_text[@]} - 2 - 1))

  local pad=$((height - (row - 1) - ${#b_text[@]} - 2))
  [ "$pad" -ge 1 ] || pad=1
  for ((i = 0; i < pad; i++)); do out+="${ESC}[K"$'\n'; done
  row=$((row + pad))
  todo_top=$row todo_bottom=$((row + b_todo_end - 1))
  issue_top=0 issue_bottom=-1
  if [ "$b_issue_start" -ge 0 ]; then
    issue_top=$((row + b_issue_start)) issue_bottom=$((row + ${#b_text[@]} - 1))
  fi
  for i in "${!b_text[@]}"; do
    out+="${b_text[i]}${ESC}[K"$'\n'
    [ -n "${b_click[i]}" ] && click[$row]=${b_click[i]}
    row=$((row + 1))
  done

  local footer="q close · R refresh · / filter"
  [ "$nav" = 1 ] && footer="⏎ open · / filter · n new · esc"
  [ "$nav" = 1 ] && [ -n "$issue_filter" ] && footer="⏎ open · esc clear filter"
  [ "$filter_typing" = 1 ] && footer="filtering · ⏎ keep · esc clear"
  out+="${ESC}[K"$'\n'"${DIM}  ${footer}${RESET}${ESC}[K"

  # Rows you can act on, top to bottom, for keyboard mode (the whole tree and all todos,
  # also those scrolled out of view); and its highlight: a grey bar across the selected
  # row, kept through the row's own colour resets
  local r sel_row=''
  nav_order=()
  for r in "${tree_click[@]}"; do [ -n "$r" ] && nav_order+=("$r"); done
  nav_order+=("${b_nav[@]}")
  nav_seen=$nav_target
  if [ "$nav" = 1 ]; then
    for ((r = 1; r <= height; r++)); do
      [ "${click[$r]:-}" = "$nav_target" ] && sel_row=$r
    done
  fi
  if [ -n "$sel_row" ]; then
    local -a frame
    mapfile -t frame <<<"$out"
    local SELBG="${ESC}[48;5;238m" line=${frame[sel_row - 1]}
    line="${line%"${ESC}[K"}"
    [ "${line:0:1}" = " " ] && line="${ESC}[38;5;215m▸${RESET}${line:1}"
    frame[sel_row - 1]="${SELBG}${line//$RESET/$RESET$SELBG}${ESC}[K${RESET}"
    printf -v out '%s\n' "${frame[@]}"
    out=${out%$'\n'}
  fi
  # Synchronized output (mode 2026): tmux shows the frame only once it is complete.
  # Unchanged frames are not sent again: tmux keeps the pane's contents, and every
  # redraw under an open popup made tmux repaint the popup over it (a flicker every 2s)
  if [ "$out" != "$last_frame" ]; then
    printf '%s' "${ESC}[?2026h${ESC}[H$out${ESC}[J${ESC}[?2026l"
    last_frame=$out
  fi
}
