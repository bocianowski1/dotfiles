local find_cmd = {
  "fd",
  "--type",
  "f",
  "--hidden",
  "--exclude",
  ".git",
  "--exclude",
  "_build",
  "--exclude",
  "deps",
  "--exclude",
  ".elixir_ls",
}

return {
  "nvim-telescope/telescope.nvim",
  dependencies = { "nvim-lua/plenary.nvim" },
  opts = {
    pickers = {
      find_files = {
        hidden = true,
        find_command = find_cmd,
      },
    },
  },
  keys = {
    {
      "<leader><space>",
      function()
        require("telescope.builtin").find_files({
          find_command = find_cmd,
        })
      end,
      desc = "Find Files (Root Dir)",
    },
  },
}
