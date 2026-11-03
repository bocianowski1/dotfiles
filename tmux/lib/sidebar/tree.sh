# shellcheck shell=bash
# shellcheck disable=SC2034,SC2154 # render's state, shared by the sidebar files (render.sh)
# The window tree at the top: each window of the session, and under it its Claude sessions
# with a state dot. It gets the rows the bottom block leaves and scrolls when they are too
# few. Works on render's locals (tree_offset, click, nav_*) and compose_frame's.
BLINK_SECONDS=30 # a session that just answered blinks this long

# The whole tree from tree_panes (FMT lines) into tree_text / tree_click
tree_build() {
  local ESC=$'\e'
  local RESET="${ESC}[0m" BOLD="${ESC}[1m" DIM="${ESC}[38;5;245m"
  local ACTIVE="${ESC}[38;5;215m" WINDOW="${ESC}[38;5;110m" MARKED="${ESC}[38;5;114m"
  local today last_win='' colour when day name room line dot marker max tag
  local wid pid widx wname wactive pactive state title path cmd sidebar opened marked replied linked
  printf -v today '%(%F)T' -1
  tree_text=() tree_click=()
  while IFS=$US read -r wid pid widx wname wactive pactive state title path cmd sidebar opened marked replied linked; do
    if [ "$widx" != "$last_win" ]; then
      [ -n "$last_win" ] && tree_text+=("") tree_click+=("")
      colour=$WINDOW
      [ "$marked" = 1 ] && colour=$MARKED
      [ "$wactive" = 1 ] && colour=$ACTIVE # the window you are in stays orange, marked or not

      # When you last switched to this window: "10:15" today, "31.10" on earlier days
      when=''
      if [ -n "$opened" ]; then
        printf -v day '%(%F)T' "$opened"
        if [ "$day" = "$today" ]; then printf -v when '%(%H:%M)T' "$opened"; else printf -v when '%(%d.%m)T' "$opened"; fi
      fi
      name=" ${widx} ${wname}" room=$((width - 7))
      [ ${#name} -gt "$room" ] && name="${name:0:room-1}…"
      printf -v line '%s%s%-*s%s %s' "$colour" "$BOLD" "$room" "$name" "$RESET$DIM" "$when"
      tree_text+=("$line${RESET}") tree_click+=("$wid")
      last_win=$widx
    fi
    [ "$sidebar" != 1 ] || continue
    [ -n "$state" ] || [ "$cmd" = claude ] || continue

    # Claude's pane title is "<spinner> <task summary>"; fall back to the directory name
    title=${title#"${title%%[[:alnum:]]*}"}
    case $title in "" | */* | "$host") title=${path##*/} ;; esac
    # red: waiting on you · green: working · orange: answered in the last recent_minutes
    case $state in
    attention) dot="${ESC}[1;38;5;203m●" ;;
    running) dot="${ESC}[38;5;114m●" ;;
    idle)
      dot="${ESC}[38;5;245m●"
      if [ -n "$replied" ] && [ $((EPOCHSECONDS - replied)) -lt $((recent_minutes * 60)) ]; then
        dot="${ESC}[38;5;214m●"
        # Blinking at first: the terminal blinks it (SGR 5), so no redraws
        [ $((EPOCHSECONDS - replied)) -lt "$BLINK_SECONDS" ] && dot="${ESC}[5;38;5;214m●"
      fi
      ;;
    *) dot="${ESC}[38;5;240m○" ;; # Claude is running, but its hooks have not reported yet
    esac
    marker=' '
    [ "$wactive$pactive" = 11 ] && marker='▸'
    # "#107": the issue the session works on (started with c in the issue popup)
    max=$((width - 7)) tag=''
    [[ $linked =~ /issues/([0-9]+)$ ]] && tag="#${BASH_REMATCH[1]}" max=$((max - ${#tag} - 1))
    [ ${#title} -gt "$max" ] && title="${title:0:max-1}…"
    printf -v line '  %s %-*s %s%s' "$marker" "$max" "$title" "${tag:+$DIM$tag$RESET }" "$dot"
    tree_text+=("$line${RESET}") tree_click+=("$pid")
  done < <(printf '%s\n' "${tree_panes[@]}")
}

# The header and the visible part of the tree into out (from row 3), with <rows> rows at
# most; sets click, row, tree_top and tree_bottom. Keeps a keyboard selection in view.
tree_draw() { # <rows>
  local ESC=$'\e'
  local RESET="${ESC}[0m" BOLD="${ESC}[1m" DIM="${ESC}[38;5;245m"
  local total=${#tree_text[@]} rows=$1 i
  [ "$rows" -ge 1 ] || rows=1
  [ "$rows" -le "$total" ] || rows=$total
  if [ "$nav" = 1 ] && [ "$nav_target" != "$nav_seen" ]; then
    for i in "${!tree_click[@]}"; do
      [ "${tree_click[i]}" = "$nav_target" ] || continue
      [ "$i" -ge "$tree_offset" ] || tree_offset=$i
      [ "$i" -lt $((tree_offset + rows)) ] || tree_offset=$((i - rows + 1))
    done
  fi
  [ "$tree_offset" -le $((total - rows)) ] || tree_offset=$((total - rows))
  [ "$tree_offset" -ge 0 ] || tree_offset=0

  # Scrolled, the header says how many windows there are: "Windows (8)"; on the right
  # "● 15m", how long the orange "answered recently" dot lasts (a click changes it), and
  # what the scroll hides
  local more title=" Claude Code" n=0 right gap
  scroll_marks "$tree_offset" $((total - tree_offset - rows))
  if [ "$rows" -lt "$total" ]; then
    for i in "${tree_click[@]}"; do [[ $i == @* ]] && n=$((n + 1)); done
    title=" Windows ($n)"
  fi
  right="● ${recent_minutes}m${more:+ $more}"
  printf -v gap '%*s' $((width - ${#title} - ${#right} - 1)) ''
  out="$BOLD$title$RESET$gap${ESC}[38;5;214m●$RESET$DIM ${recent_minutes}m${more:+ $more}$RESET${ESC}[K"$'\n'"${ESC}[K"$'\n'
  click[1]=recent
  row=3 tree_top=3
  for ((i = tree_offset; i < tree_offset + rows; i++)); do
    out+="${tree_text[i]}${ESC}[K"$'\n'
    [ -n "${tree_click[i]}" ] && click[$row]=${tree_click[i]}
    row=$((row + 1))
  done
  tree_bottom=$((row - 1))
}
