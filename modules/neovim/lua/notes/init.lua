local commands = require("notes.commands")
local pickers = require("notes.pickers")

vim.keymap.set("n", "<Tab>", commands.prompt_for_new_note)
vim.keymap.set("n", "<S-Tab>", pickers.stack_notes)
vim.keymap.set("n", "<Leader><Tab>", pickers.search_all_notes)
vim.keymap.set("n", "<Leader>d", commands.open_daily)
