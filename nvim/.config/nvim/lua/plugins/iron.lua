return {
  {
    "Vigemus/iron.nvim",
    keys = {
      { "<leader>rs", desc = "Start REPL" },
      { "<leader>rr", desc = "Restart REPL" },
      { "<leader>ro", desc = "Open/focus REPL" },
      { "<leader>rh", desc = "Hide REPL" },
      { "<leader>rq", desc = "Exit REPL" },
      { "<leader>rl", desc = "Send line" },
      { "<leader>rp", desc = "Send paragraph" },
      { "<leader>rf", desc = "Send file" },
      { "<leader>rm", desc = "Send motion" },
      { "<leader>rv", desc = "Send visual selection", mode = "v" },
      { "<leader>rc", desc = "Clear REPL" },
      { "<leader>ri", desc = "Interrupt REPL" },
      { "<leader>r<cr>", desc = "Send return to REPL" },
    },
    config = function()
      local iron = require("iron.core")
      local view = require("iron.view")

      iron.setup({
        config = {
          scratch_repl = true,
          repl_definition = {
            python = {
              command = { "python3" },
              format = require("iron.fts.common").bracketed_paste,
            },
          },
          repl_open_cmd = view.split.vertical.botright(0.4),
        },
        keymaps = {
          send_motion = "<leader>rm",
          visual_send = "<leader>rv",
          send_file = "<leader>rf",
          send_line = "<leader>rl",
          send_paragraph = "<leader>rp",
          send_mark = "<leader>r.",
          cr = "<leader>r<cr>",
          interrupt = "<leader>ri",
          exit = "<leader>rq",
          clear = "<leader>rc",
        },
        highlight = {
          italic = true,
        },
        ignore_blank_lines = true,
      })

      vim.keymap.set("n", "<leader>rs", "<cmd>IronRepl<cr>", { desc = "Start REPL" })
      vim.keymap.set("n", "<leader>rr", "<cmd>IronRestart<cr>", { desc = "Restart REPL" })
      vim.keymap.set("n", "<leader>ro", "<cmd>IronFocus<cr>", { desc = "Open/focus REPL" })
      vim.keymap.set("n", "<leader>rh", "<cmd>IronHide<cr>", { desc = "Hide REPL" })
    end,
  },
}
