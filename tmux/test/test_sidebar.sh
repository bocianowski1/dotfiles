# The sidebar as you see it: a real sidebar in a test tmux server, read off its screen.
# shellcheck disable=SC2034 # (variables the helpers read)

test_header_when_everything_fits() {
  start_tmux 200 50
  add_session "$(first_window)" "first session" >/dev/null
  start_sidebars
  assert_match '^ Claude Code +● 15m$' "$(line 1)" "header"
  assert_match '^ 0 ' "$(line 3)" "first window"
}

test_short_narrow_pane_keeps_its_top() {
  # 25 wide in a 60 wide window (too narrow to be put back to 34): nothing may wrap,
  # and the frame may not grow taller than the pane
  todos 6
  issues 24
  start_tmux 60 28
  local i
  for i in 1 2 3 4 5 6 7; do add_window >/dev/null; done
  for w in $(tm list-windows -t main -F '#{window_id}'); do add_session "$w" "s" >/dev/null; done
  start_sidebars 25
  assert_match '^ Windows \(8\) ' "$(line 1)" "header"
  assert_match '^ 0 ' "$(line 3)" "first window"
  assert_eq 28 "$(screen | wc -l)" "rows"
  assert_match 'q close' "$(line 28)" "footer on the last row"
}

test_window_list_scrolls() {
  issues 3
  start_tmux 200 22
  local i
  for i in 1 2 3 4 5 6 7; do add_window >/dev/null; done
  start_sidebars
  wait_for '^ Windows \(8\) +● 15m ↓'
  wheel down 4
  wait_for '^ Windows \(8\) +● 15m ↑1 ↓'
  wheel up 4
  wait_for '^ Windows \(8\) +● 15m ↓'
}

test_wheel_scrolls_only_the_list_under_it() {
  issues 24
  meetings "$((EPOCHSECONDS + 86400)) Standup"
  start_tmux 200 50
  start_sidebars
  wait_for 'Issues +1–8 of 24'
  wheel down "$(row_of 'Standup')"
  sleep 0.3
  wait_for 'Issues +1–8 of 24'
  wheel down "$(row_of 'repo#2 ')"
  wait_for 'Issues +2–9 of 24'
}

test_todo_count_and_scrolling() {
  todos 12
  start_tmux 200 50
  start_sidebars
  wait_for '^ Todo \(12\) ↓7 +a add · e edit$'
  wheel down "$(row_of 'todo 1$')"
  wait_for '^ Todo \(12\) ↑1 ↓6 '
}

test_click_ticks_off_a_todo() {
  todos 3
  start_tmux 200 50
  start_sidebars
  click "$(row_of '○ todo 2$')"
  wait_gone '○ todo 2$'
  wait_for '^ Todo \(2\)'
  assert_eq "- [x] todo 2" "$(sed -n 2p "$HOME/.config/claude-sidebar/todo.md")" "todo file"
}

test_keyboard_mode_reaches_rows_out_of_view() {
  todos 12
  start_tmux 200 50
  start_sidebars
  tm select-pane -t "$(sidebar)"
  keys C-e
  local i
  for i in $(seq 30); do
    keys j
    screen | grep -q '^ Todo (12) ↑' && break
  done
  wait_for '^ Todo \(12\) ↑'
  keys Enter
  wait_for '^ Todo \(11\)'
}

test_dot_colours() {
  start_tmux 200 50
  local w now=$EPOCHSECONDS
  w=$(first_window)
  add_session "$w" "waiting" attention >/dev/null
  add_session "$w" "working" running >/dev/null
  add_session "$w" "just answered" idle "$now" >/dev/null
  add_session "$w" "answered earlier" idle $((now - 300)) >/dev/null
  add_session "$w" "answered long ago" idle $((now - 3600)) >/dev/null
  start_sidebars
  wait_for 'answered long ago'
  local raw
  raw=$(screen_raw)
  assert_match '38;5;203m●' "$(grep -a 'waiting' <<<"$raw")" "red: waiting on you"
  assert_match '38;5;114m●' "$(grep -a 'working' <<<"$raw")" "green: working"
  assert_match "$ESC\[5m$ESC\[38;5;214m●" "$(grep -a 'just answered' <<<"$raw")" "orange, blinking"
  assert_match "38;5;214m●" "$(grep -a 'answered earlier' <<<"$raw")" "orange"
  assert_no_match "$ESC\[5m" "$(grep -a 'answered earlier' <<<"$raw")" "not blinking"
  assert_match '38;5;245m●' "$(grep -a 'answered long ago' <<<"$raw")" "grey"
}

test_recent_minutes_setting() {
  setting recent-minutes 30
  start_tmux 200 50
  add_session "$(first_window)" "answered 20m ago" idle $((EPOCHSECONDS - 1200)) >/dev/null
  start_sidebars
  wait_for '● 30m$'
  assert_match '38;5;214m●' "$(screen_raw | grep -a 'answered 20m ago')" "orange within 30m"
  click 1
  wait_for '● 60m$'
  assert_eq 60 "$(cat "$HOME/.config/claude-sidebar/recent-minutes")" "setting file"
}

test_marked_window_is_green() {
  start_tmux 200 50
  local w
  w=$(add_window marked)
  start_sidebars
  "$BIN/claude-sidebar" mark "$w"
  sleep 0.5
  assert_match '38;5;114m.* 1 marked' "$(screen_raw | grep -a ' 1 marked')" "marked window"
}

test_sidebar_goes_back_to_34_columns() {
  start_tmux 200 40
  start_sidebars 54
  local i
  for i in $(seq 40); do
    [ "$(tm display -p -t "$(sidebar)" '#{pane_width}')" = 34 ] && return 0
    sleep 0.1
  done
  fail "sidebar is $(tm display -p -t "$(sidebar)" '#{pane_width}') wide"
}

test_session_shows_its_issue() {
  issues 5
  start_tmux 200 50
  add_session "$(first_window)" "fixing it" running "" "https://github.com/owner/repo/issues/3" >/dev/null
  start_sidebars
  wait_for 'fixing it +#3 ●'
  wait_for '^ ◆  repo#3 issue 3$'
  wait_for '^    repo#2 issue 2$'
}

test_calendar_shows_tomorrow() {
  meetings "$((EPOCHSECONDS + 86400)) Standup"
  start_tmux 200 50
  start_sidebars
  wait_for '^ No meetings today$'
  wait_for '^ Tomorrow$'
  wait_for '^  [0-9]{2}:[0-9]{2} Standup'
}

test_calendar_empty_week() {
  meetings
  start_tmux 200 50
  start_sidebars
  wait_for '^ No meetings this week$'
  assert_no_match 'Today|Tomorrow' "$(screen)" "nothing else in the calendar"
}
