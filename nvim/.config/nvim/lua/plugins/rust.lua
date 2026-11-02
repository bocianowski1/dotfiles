return {
  -- Rust LSP (rust-analyzer from rustup) via rustaceanvim, enabled by the lang.rust extra
  {
    "mrcjkb/rustaceanvim",
    opts = {
      server = {
        default_settings = {
          ["rust-analyzer"] = {
            check = { command = "clippy" },
            completion = { autoimport = { enable = true } },
          },
        },
      },
    },
  },
  {
    "nvim-treesitter/nvim-treesitter",
    opts = { ensure_installed = { "rust", "ron", "toml" } },
  },
}
