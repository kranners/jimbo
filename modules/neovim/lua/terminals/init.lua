local commands = require("terminals.commands")

vim.keymap.set("n", "=", commands.open_terminal_vertical)
vim.keymap.set("n", "+", commands.open_terminal_horizontal)
