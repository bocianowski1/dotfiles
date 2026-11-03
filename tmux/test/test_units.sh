# shellcheck shell=bash
# Single functions, sourced from tmux/lib and the scripts, with fixed inputs.
# shellcheck disable=SC2034,SC2154 # (variables the functions under test read and set)

load_sidebar() { # <parts...>
  self=$BIN/claude-sidebar
  # shellcheck source=../lib/common.sh
  source "$LIB/common.sh"
  # shellcheck source=../lib/sidebar/core.sh
  source "$LIB/sidebar/core.sh"
  local part
  for part; do
    # shellcheck source=/dev/null
    source "$LIB/sidebar/$part.sh"
  done
}

plain() { sed "s/$ESC\[[0-9;]*m//g"; } # without colours

# calendar_lines at a fixed time (Tuesday 3 November 2026, 10:00 local) over meetings
# given as "YYYY-MM-DD HH:MM title"
calendar_at() { # <now "YYYY-MM-DD HH:MM"> <meetings...>
  local now m rows=()
  now=$(date -d "$1" +%s)
  shift
  for m in "$@"; do rows+=("$(date -d "${m:0:16}" +%s) ${m:17}"); done
  meetings "${rows[@]}"
  calendar_lines 34 "$now"
  printf '%s\n' "${cal_lines[@]}" | plain | sed 's/ *$//'
}

test_calendar_cases() {
  load_sidebar calendar
  local tue="2026-11-03 10:00"
  assert_eq " No meetings this week" "$(calendar_at "$tue")" "empty"
  assert_eq $' No meetings today\n\n Thursday 05.11\n  09:00 Planning' \
    "$(calendar_at "$tue" "2026-11-05 09:00 Planning" "2026-11-06 13:00 Later")" "next this week"
  assert_eq $' No meetings today\n\n Tomorrow\n  09:00 Standup' \
    "$(calendar_at "$tue" "2026-11-04 09:00 Standup")" "tomorrow"
  assert_eq $' Today\n  14:00 Review' \
    "$(calendar_at "$tue" "2026-11-03 14:00 Review" "2026-11-05 09:00 Thu")" "today, not later days"
  assert_eq $' No meetings today\n\n Thursday 05.11\n  09:00 Thu' \
    "$(calendar_at "$tue" "2026-11-03 08:00 Over" "2026-11-05 09:00 Thu")" "today's are over"
  assert_eq " No meetings this week" "$(calendar_at "$tue" "2026-11-09 09:00 Next week")" "next week only"
  assert_eq $' No meetings today\n\n Tomorrow\n  09:00 Monday' \
    "$(calendar_at "2026-11-08 10:00" "2026-11-09 09:00 Monday")" "Sunday: tomorrow is next week"
  assert_eq $' No meetings today\n\n Sunday 08.11\n  09:00 Sun' \
    "$(calendar_at "2026-11-06 10:00" "2026-11-08 09:00 Sun")" "Friday: Sunday is this week"
  assert_eq $' Today\n  10:25 Soon               in 10m' \
    "$(calendar_at "2026-11-03 10:15" "2026-11-03 10:25 Soon")" "in 10m"
  assert_eq $' Today\n  10:00 Now                   now' \
    "$(calendar_at "2026-11-03 10:15" "2026-11-03 10:00 Now")" "running now"
}

test_todo_tick() {
  load_sidebar todo
  printf '  - [ ] indented\n- [x] done\nplain\n- [ ] last, no newline' >"$TODO_FILE"
  local n
  for n in 1 2 3 4 99; do todo_tick "$n"; done
  assert_eq $'  - [x] indented\n- [x] done\nplain\n- [x] last, no newline' "$(cat "$TODO_FILE")"
}

test_todo_lines() {
  load_sidebar todo
  local nav=0 nav_target='' nav_seen='' todo_offset=0
  todos 7
  todo_lines 34
  assert_eq " Todo (7) ↓2       a add · e edit" "$(plain <<<"${todo_lines[0]}")" "header"
  assert_eq "6 7" "${#todo_lines[@]} ${#todo_all[@]}" "rows shown, all"
  assert_eq "1 2 3 4 5" "${todo_refs[*]:1}" "line numbers"
  todo_offset=99
  todo_lines 20
  assert_eq " Todo (7) ↑2" "$(plain <<<"${todo_lines[0]}" | sed 's/ *$//')" "scrolled to the end, no room for the hint"
  todos 0
  todo_lines 34
  assert_eq "  Nothing to do" "$(plain <<<"${todo_lines[1]}")" "empty"
}

test_scroll_marks() {
  load_sidebar
  local more
  scroll_marks 0 0 && assert_eq "" "$more"
  scroll_marks 2 0 && assert_eq "↑2" "$more"
  scroll_marks 0 5 && assert_eq "↓5" "$more"
  scroll_marks 2 -3 && assert_eq "↑2" "$more"
  scroll_marks 3 4 && assert_eq "↑3 ↓4" "$more"
}

test_minutes_settings() {
  load_sidebar
  local minutes f=$HOME/.config/claude-sidebar/test-minutes
  minutes_setting "$f" && assert_eq 15 "$minutes" "no file"
  echo nonsense >"$f"
  minutes_setting "$f" && assert_eq 15 "$minutes" "not a number"
  local seen=()
  for _ in 1 2 3 4; do
    minutes_cycle "$f"
    seen+=("$(cat "$f")")
  done
  assert_eq "30 60 5 15" "${seen[*]}" "cycle from nonsense (read as 15), around after 60"
}

test_branch_names() {
  # shellcheck source=../bin/claude-issue
  source "$BIN/claude-issue"
  assert_eq "feat/12-add-a-login-page" "$(branch_name 12 "Add a login page" "")"
  assert_eq "fix/7-krasj-pa-forside-nar" "$(branch_name 7 "Krasj på forside (når?)" "enhancement,Bug")"
  assert_eq "feat/3-$(printf 'a%.0s' {1..40})" "$(branch_name 3 "$(printf 'a%.0s' {1..60})" "")" "40 characters at most"
}

test_c_goes_to_a_running_session_on_the_issue() {
  start_tmux 120 30
  local url=https://github.com/owner/repo/issues/5 existing other
  existing=$(add_session "$(first_window)" "on it" running "" "$url")
  other=$(add_session "$(first_window)" "ended" "" "" "https://github.com/owner/repo/issues/6")
  tm set -pu -t "$other" @claude_state
  # shellcheck source=../bin/claude-issue
  source "$BIN/claude-issue"
  find_clone() { echo /tmp; }
  CLAUDE_ISSUE_DRYRUN=1
  start_claude owner/repo 5 "t" "" "$url" "$(first_window)"
  assert_eq "existing $existing" "$(cat "$PROMPTS/dryrun.txt")" "an issue with a running session"
  start_claude owner/repo 6 "t" "" "https://github.com/owner/repo/issues/6" "$(first_window)"
  assert_match '^tmux split-window .*-P' "$(cat "$PROMPTS/dryrun.txt")" "the session on #6 ended: a new one"
  assert_match 'Work on GitHub issue owner/repo#6' "$(cat "$PROMPTS/owner-repo-6.md")" "prompt"
}

test_claude_issues_merges_created_and_closed() {
  # gh lists #1 (assigned) and #2 (yours, also assigned); #9 was just created here and is
  # not listed yet; #2 was just closed here and is still listed
  cat >"$HOME/bin/gh" <<'EOF'
#!/bin/sh
case "$*" in
*--assignee*) printf '2026-11-03T10:00:00Z\trepo\t1\t1\tone\thttps://github.com/o/repo/issues/1\n2026-11-02T10:00:00Z\trepo\t2\t1\ttwo\thttps://github.com/o/repo/issues/2\n' ;;
*--author*) printf '2026-11-02T10:00:00Z\trepo\t2\t0\ttwo\thttps://github.com/o/repo/issues/2\n' ;;
esac
EOF
  local cache=$HOME/.cache/claude-sidebar
  printf '%s\trepo\t9\t0\tnew\thttps://github.com/o/repo/issues/9\n' "$EPOCHSECONDS" >"$cache/created.tsv"
  printf 'https://github.com/o/repo/issues/2\t%s\n' "$EPOCHSECONDS" >"$cache/closed.tsv"
  "$BIN/claude-issues" || fail "claude-issues failed"
  assert_eq $'repo\t9\t0\tnew\thttps://github.com/o/repo/issues/9\nrepo\t1\t1\tone\thttps://github.com/o/repo/issues/1' \
    "$(cat "$cache/issues.tsv")" "issues.tsv"
}

test_calendar_fetcher() {
  command -v uv >/dev/null || return 0 # (needs uv for its packages)
  local day1 day2
  # Tomorrow and the day after, at 09:00 UTC; and a cancelled one tomorrow
  day1=$(date -u -d tomorrow +%Y%m%d) day2=$(date -u -d '2 days' +%Y%m%d)
  cat >"$HOME/test.ics" <<EOF
BEGIN:VCALENDAR
VERSION:2.0
PRODID:test
BEGIN:VEVENT
UID:1
DTSTART:${day1}T090000Z
DTEND:${day1}T093000Z
SUMMARY:Standup
X-MICROSOFT-SKYPETEAMSMEETINGURL:https://teams.microsoft.com/l/meetup-join/abc
END:VEVENT
BEGIN:VEVENT
UID:2
DTSTART:${day1}T100000Z
DTEND:${day1}T103000Z
SUMMARY:Avlyst: Old meeting
END:VEVENT
BEGIN:VEVENT
UID:3
DTSTART:${day2}T090000Z
DTEND:${day2}T093000Z
SUMMARY:Day after
END:VEVENT
END:VCALENDAR
EOF
  UV_CACHE_DIR=$(HOME=$REAL_HOME uv cache dir) "$BIN/claude-calendar" --file "$HOME/test.ics" || fail "claude-calendar failed"
  local got
  got=$(cut -f3,4 "$HOME/.cache/claude-sidebar/calendar.tsv")
  assert_match $'^Standup\thttps://teams.microsoft.com/l/meetup-join/abc' "$got" "the first meeting, with its link"
  assert_no_match 'Old meeting' "$got" "cancelled"
  # The day after tomorrow is in only when it is still this week
  if [ "$(date -d '2 days' +%u)" -gt "$(date +%u)" ]; then
    assert_match 'Day after' "$got" "later this week"
  fi
}
