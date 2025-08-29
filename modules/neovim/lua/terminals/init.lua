local commands = require("terminals.commands")

vim.keymap.set("n", "=", commands.open_terminal_vertical)
vim.keymap.set("n", "+", commands.open_terminal_horizontal)

vim.api.nvim_create_autocmd("TermOpen", {
  callback = function()
    vim.opt_local.number = true
    vim.opt_local.relativenumber = true
  end,
})
