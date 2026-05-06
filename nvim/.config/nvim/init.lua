-- bootstrap lazy.nvim, LazyVim and your plugins
require("config.lazy")
vim.keymap.set("n", "<F2>", vim.lsp.buf.rename, { desc = "Rename symbol" }) -- but <leader>cr works
