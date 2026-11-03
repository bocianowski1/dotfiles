# shellcheck shell=bash
# The issue popup (claude-issue view), with a gh that prints a made-up issue.

fake_issue_gh() {
  cat >"$HOME/bin/gh" <<'GH'
#!/bin/sh
case "$*" in
*--json*) printf 'Fix the thing\nbug\nSome body text\n' ;;
*) printf 'Fix the thing owner/repo#%s\n\n  Some body text\n\nView this issue on GitHub\n' "$3" ;;
esac
GH
}

test_issue_popup_keys() {
  fake_issue_gh
  issues 6
  start_tmux 160 40
  local p
  p=$(tm split-window -d -P -F '#{pane_id}' -t main "'$BIN/claude-issue' view https://github.com/owner/repo/issues/5 main:0")
  popup() { tm capture-pane -p -t "$p" | sed 's/ *$//'; }
  for _ in $(seq 50); do
    popup | grep -q 'Some body text' && break
    sleep 0.1
  done
  assert_match 'Fix the thing owner/repo#5' "$(popup)" "the issue"
  assert_match '↑/↓ issue 5/6 · o browser · s copy link' "$(popup | tail -1)" "footer"
  tm send-keys -t "$p" s
  for _ in $(seq 20); do
    [ -s "$HOME/clipboard" ] && break
    sleep 0.1
  done
  assert_eq https://github.com/owner/repo/issues/5 "$(cat "$HOME/clipboard")" "s: link on the clipboard"
  assert_match 'Copied https://github.com/owner/repo/issues/5' "$(popup | tail -1)" "s: message"
  tm send-keys -t "$p" Down
  for _ in $(seq 30); do
    popup | grep -q 'issue 6/6' && break
    sleep 0.1
  done
  assert_match 'owner/repo#6' "$(popup)" "↓: the next issue"
  assert_eq https://github.com/owner/repo/issues/6 "$(tm show -gv @claude_issue_selected)" "the sidebar follows"
}
