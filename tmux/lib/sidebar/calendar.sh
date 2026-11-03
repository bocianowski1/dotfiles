# shellcheck shell=bash
# shellcheck disable=SC2034,SC2154 # render's state, shared by the sidebar files (render.sh)
# The calendar block: today's and tomorrow's meetings, else the next one this week.
# claude-calendar fetches the meetings into CALENDAR_CACHE.
CALENDAR_URL_FILE=$CONFIG_DIR/calendar-url
CALENDAR_CACHE=~/.cache/claude-sidebar/calendar.tsv # (claude-calendar writes it here)
CALENDAR_MAX=5                                      # meetings shown

# Calendar lines for the bottom of the sidebar, into the array cal_lines (and the Teams
# join link for each line into cal_urls)
calendar_lines() { # <width> <now epoch>
  local width=$1 now=$2 ESC=$'\e'
  local RESET="${ESC}[0m" BOLD="${ESC}[1m" DIM="${ESC}[38;5;245m"
  cal_lines=() cal_urls=()
  [ -f "$CALENDAR_URL_FILE" ] || return
  local today tomorrow wday k d start end title url
  printf -v today '%(%F)T' "$now"
  printf -v tomorrow '%(%F)T' $((now + 86400))
  # The rest of this week (to Sunday) after tomorrow, by date; noon steps are safe across DST
  local -A later_day=()
  local midnight hms
  printf -v hms '%(%H %M %S %u)T' "$now"
  read -r k d start wday <<<"$hms"
  midnight=$((now - 10#$k * 3600 - 10#$d * 60 - 10#$start))
  for ((k = 2; k <= 7 - wday; k++)); do
    printf -v d '%(%F)T' $((midnight + k * 86400 + 43200))
    later_day[$d]=1
  done

  # Meetings not over yet: today's and tomorrow's (CALENDAR_MAX in all), and the first one
  # after that this week
  local -a today_rows=() tomorrow_rows=()
  local next_row='' day row
  if [ -s "$CALENDAR_CACHE" ]; then
    while IFS=$'\t' read -r start end title url; do
      [ "$end" -gt "$now" ] || continue
      printf -v day '%(%F)T' "$start"
      row="$start"$'\t'"$end"$'\t'"$title"$'\t'"$url"
      if [ "$day" = "$today" ] || [ "$day" = "$tomorrow" ]; then
        [ $((${#today_rows[@]} + ${#tomorrow_rows[@]})) -lt "$CALENDAR_MAX" ] || continue
        if [ "$day" = "$today" ]; then today_rows+=("$row"); else tomorrow_rows+=("$row"); fi
      elif [ -z "$next_row" ] && [ -n "${later_day[$day]:-}" ]; then
        next_row=$row
      fi
    done <"$CALENDAR_CACHE"
  fi

  local r
  if [ ${#today_rows[@]} -gt 0 ]; then
    cal_lines+=("${BOLD} Today${RESET}") cal_urls+=("")
    for r in "${today_rows[@]}"; do calendar_meeting "$r"; done
  elif [ ${#tomorrow_rows[@]} -gt 0 ] || [ -n "$next_row" ]; then
    cal_lines+=("${DIM} No meetings today${RESET}") cal_urls+=("")
  else
    cal_lines+=("${DIM} No meetings this week${RESET}") cal_urls+=("")
    return
  fi
  if [ ${#tomorrow_rows[@]} -gt 0 ]; then
    cal_lines+=("" "${BOLD} Tomorrow${RESET}") cal_urls+=("" "")
    for r in "${tomorrow_rows[@]}"; do calendar_meeting "$r"; done
  elif [ ${#today_rows[@]} -eq 0 ]; then
    # Nothing today or tomorrow: the next meeting this week, under its day
    local label
    printf -v label '%(%A %d.%m)T' "${next_row%%$'\t'*}"
    cal_lines+=("" "${BOLD} ${label}${RESET}") cal_urls+=("" "")
    calendar_meeting "$next_row"
  fi
}

# One meeting line (calendar_lines' locals): "now" while it runs, "in 12m" within the hour
# (orange from 10 minutes before)
calendar_meeting() { # <cache row>
  local start end title url tag='' tagc=$DIM mins hhmm max=$((width - 16)) line
  IFS=$'\t' read -r start end title url <<<"$1"
  mins=$(((start - now + 59) / 60))
  if [ "$start" -le "$now" ]; then
    tag=now tagc="${ESC}[38;5;114m"
  elif [ "$mins" -le 60 ]; then
    tag="in ${mins}m"
    [ "$mins" -le 10 ] && tagc="${ESC}[1;38;5;214m"
  fi
  printf -v hhmm '%(%H:%M)T' "$start"
  [ ${#title} -gt "$max" ] && title="${title:0:max-1}…"
  printf -v line '  %s%s%s %-*s %s%6s%s' "$DIM" "$hhmm" "$RESET" "$max" "$title" "$tagc" "$tag" "$RESET"
  cal_lines+=("$line") cal_urls+=("$url")
}

# Refresh the calendar cache in the background every 5 minutes, or now with "force"
# (CLAUDE_SIDEBAR_NO_FETCH=1, as in the tests: never)
calendar_fetch() { # [force]
  [ -z "${CLAUDE_SIDEBAR_NO_FETCH:-}" ] || return 0
  [ -f "$CALENDAR_URL_FILE" ] || return
  local age=999999
  [ -f "$CALENDAR_CACHE" ] && age=$((EPOCHSECONDS - $(stat -c %Y "$CALENDAR_CACHE")))
  [ "${1:-}" = force ] || [ "$age" -ge 300 ] || return
  mkdir -p "${CALENDAR_CACHE%/*}"
  { flock -n "${CALENDAR_CACHE%/*}/fetch.lock" "${self%/*}/claude-calendar" && "$self" refresh; } </dev/null >/dev/null 2>&1 &
}
