# shellcheck shell=bash
# shellcheck disable=SC2034,SC2154 # render's state, shared by the sidebar files (render.sh)
# The todo block: open items of TODO_FILE ("- [ ] ..." lines), ticked off by a click.
TODO_FILE=$CONFIG_DIR/todo.md
TODO_ROWS=5 # items visible at once; the mouse wheel (or j/k) scrolls through the rest

# Open todo items: all of them into todo_all / todo_all_refs (the file line number of each,
# so a click can tick that line off), and the visible window from todo_offset, with the
# header, into todo_lines / todo_refs. Keeps a keyboard selection on a todo in view.
todo_lines() { # <width>
  local width=$1 ESC=$'\e'
  local RESET="${ESC}[0m" BOLD="${ESC}[1m" DIM="${ESC}[38;5;245m"
  todo_lines=() todo_refs=() todo_all=() todo_all_refs=()

  local lineno=0 text max=$((width - 5))
  if [ -f "$TODO_FILE" ]; then
    while IFS= read -r text || [ -n "$text" ]; do
      lineno=$((lineno + 1))
      [[ $text =~ ^[[:space:]]*-\ \[\ \]\  ]] || continue
      text=${text#*- \[ \] }
      [ ${#text} -gt "$max" ] && text="${text:0:max-1}…"
      todo_all+=("  ${DIM}○${RESET} $text") todo_all_refs+=("$lineno")
    done <"$TODO_FILE"
  fi
  local total=${#todo_all[@]}
  if [ "${nav:-0}" = 1 ] && [ "$nav_target" != "$nav_seen" ] && [[ $nav_target == todo:* ]]; then
    local i
    for i in "${!todo_all_refs[@]}"; do
      [ "todo:${todo_all_refs[i]}" = "$nav_target" ] || continue
      [ "$i" -ge "$todo_offset" ] || todo_offset=$i
      [ "$i" -lt $((todo_offset + TODO_ROWS)) ] || todo_offset=$((i - TODO_ROWS + 1))
    done
  fi
  local last=$((total - TODO_ROWS))
  [ "$last" -ge 0 ] || last=0
  [ "$todo_offset" -le "$last" ] || todo_offset=$last
  [ "$todo_offset" -ge 0 ] || todo_offset=0

  local head title=" Todo" more
  [ "$total" -gt 0 ] && title+=" ($total)"
  scroll_marks "$todo_offset" $((total - todo_offset - TODO_ROWS))
  # The key hint only when it fits
  local hint="a add · e edit" room=$((width - ${#title} - ${#more} - 2))
  [ "$room" -ge ${#hint} ] || hint=''
  printf -v head '%s%s%s %s%*s%s' "$BOLD" "$title" "$RESET$DIM" "$more" $((room + 1)) "$hint" "$RESET"
  todo_lines+=("$head") todo_refs+=(edit)
  todo_lines+=("${todo_all[@]:todo_offset:TODO_ROWS}") todo_refs+=("${todo_all_refs[@]:todo_offset:TODO_ROWS}")
  [ "$total" -gt 0 ] || { todo_lines+=("${DIM}  Nothing to do${RESET}") todo_refs+=(""); }
}

# Tick off line <n> of TODO_FILE, only if it is still an open item (the file may have
# changed). In bash, no sed: a click on a todo redraws straight after this.
todo_tick() { # <line number>
  local -a todo_file
  local i=$(($1 - 1)) re='^([[:space:]]*)- \[ \] (.*)$'
  mapfile -t todo_file 2>/dev/null <"$TODO_FILE" || return
  [[ ${todo_file[i]:-} =~ $re ]] || return
  todo_file[i]="${BASH_REMATCH[1]}- [x] ${BASH_REMATCH[2]}"
  printf '%s\n' "${todo_file[@]}" >"$TODO_FILE"
}

# A new todo (prefix T, a): a one-line popup that reads it itself (todo_read), so tmux
# never parses (or expands $ in) the text
todo_prompt() {
  tmux display-popup -E -w 60% -h 3 -T " New todo " "'$self' todo-read"
}
todo_read() {
  local text
  read -r -e -p " " text || return 0
  text=$(printf '%s' "$text" | tr -s '[:space:]' ' ' | sed 's/^ //; s/ $//')
  [ -n "$text" ] || return 0
  mkdir -p "${TODO_FILE%/*}"
  [ -s "$TODO_FILE" ] && [ -n "$(tail -c1 "$TODO_FILE")" ] && echo >>"$TODO_FILE"
  printf -- '- [ ] %s\n' "$text" >>"$TODO_FILE"
  refresh_others
}
todo_edit() { # the whole file in $EDITOR (e, a click on the header)
  mkdir -p "${TODO_FILE%/*}"
  touch "$TODO_FILE"
  tmux display-popup -E -w 70% -h 60% -T " Todo " "${EDITOR:-nvim} '$TODO_FILE'; '$self' refresh"
}
