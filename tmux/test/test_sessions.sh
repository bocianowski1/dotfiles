# Claude sessions: the state hook (claude-tmux-state) and prefix g (claude-sessions next).

test_state_hook_records_replies() {
  start_tmux 120 30
  local p
  p=$(add_session "$(first_window)" "s" "")
  tm set -pu -t "$p" @claude_state
  TMUX_PANE=$p "$BIN/claude-tmux-state" idle # session start: no answer yet
  assert_eq "" "$(tm show -pv -t "$p" @claude_replied 2>/dev/null)" "after start"
  TMUX_PANE=$p "$BIN/claude-tmux-state" running
  TMUX_PANE=$p "$BIN/claude-tmux-state" idle # answered
  assert_match '^[0-9]+$' "$(tm show -pv -t "$p" @claude_replied)" "after an answer"
  assert_eq idle "$(tm show -pv -t "$p" @claude_state)" "state"
  TMUX_PANE=$p "$BIN/claude-tmux-state" clear
  assert_eq "" "$(tm show -pv -t "$p" @claude_replied 2>/dev/null)" "after the session ended"
}

test_prefix_g_order() {
  start_tmux 120 30
  local now=$EPOCHSECONDS w plain newest red older old
  w=$(first_window)
  plain=$(add_session "$(add_window)" "no answer yet" idle)
  newest=$(add_session "$(add_window)" "newest" idle $((now - 60)))
  red=$(add_session "$(add_window)" "waiting" attention)
  older=$(add_session "$(add_window)" "older" idle $((now - 600)))
  old=$(add_session "$(add_window)" "too old" idle $((now - 3600)))
  # switch-client needs a client: attach one on a pseudo-terminal
  script -qfc "tmux -L $SOCK attach -t main" /dev/null >/dev/null 2>&1 &
  local client= i
  for i in $(seq 50); do
    client=$(tm list-clients -F '#{client_name}' | head -1)
    [ -n "$client" ] && break
    sleep 0.1
  done
  [ -n "$client" ] || fail "no client attached"
  local seen=()
  for i in 1 2 3 4; do
    "$BIN/claude-sessions" next "$client" "$(tm display -p -c "$client" '#{pane_id}')"
    seen+=("$(tm display -p -c "$client" '#{pane_id}')")
  done
  assert_eq "$red $newest $older $red" "${seen[*]}" "red, then orange newest first, then around"
  : "$plain $old" # (never visited)
}
