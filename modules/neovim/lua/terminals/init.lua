local commands = require("terminals.commands")

vim.api.nvim_create_user_command("Z", function()
  vim.cmd("wa!")
  vim.cmd("qa!")
end, {})

vim.cmd("cabbrev wqa Z")

vim.keymap.set("n", "=", commands.open_terminal_vertical)
vim.keymap.set("n", "+", commands.open_terminal_horizontal)
