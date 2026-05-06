return {
  {
    "nvim-treesitter/nvim-treesitter",
    build = ":TSUpdate",
    opts = {
      ensure_installed = { "elixir", "eex", "heex" },
      highlight = { enable = true },
      indent = { enable = true },
    },
  },
}
