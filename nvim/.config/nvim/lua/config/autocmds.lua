-- Autocmds are automatically loaded on the VeryLazy event
-- Default autocmds that are always set: https://github.com/LazyVim/LazyVim/blob/main/lua/lazyvim/config/autocmds.lua
--
-- Add any additional autocmds here
-- with `vim.api.nvim_create_autocmd`
--
-- Or remove existing autocmds by their group name (which is prefixed with `lazyvim_` for the defaults)
-- e.g. vim.api.nvim_del_augroup_by_name("lazyvim_wrap_spell")

-- Auto-reload files changed on disk (e.g. by Claude Code in another tmux pane).
-- LazyVim already sets autoread + checktime on FocusGained; this adds polling
-- so changes show up even while nvim keeps focus.
vim.o.autoread = true
local reload_timer = vim.uv.new_timer()
reload_timer:start(1000, 1000, vim.schedule_wrap(function()
  if vim.fn.mode() == "n" and vim.fn.getcmdwintype() == "" then
    vim.cmd("silent! checktime")
  end
end))
