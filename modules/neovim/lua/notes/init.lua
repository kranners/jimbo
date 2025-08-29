local constants = require("notes.constants")
local commands = require("notes.commands")
local pickers = require("notes.pickers")

local is_darwin = vim.fn.has("macunix") == 1

require("obsidian").setup({
  daily_notes = { date_format = "%Y/%m/%d %B, %Y", template = "Daily.md" },
  open_notes_in = "current",
  templates = { subdir = constants.latte_root .. "/Templates" },
  disable_frontmatter = true,
  ui = {
    checkboxes = {
      [" "] = { char = " ", hl_group = "ObsidianTodo", order = 100 },
      ["~"] = { char = "~", hl_group = "ObsidianTilde", order = 200 },
      ["x"] = { char = "x", hl_group = "ObsidianDone", order = 300 },
    },
    enable = false,
  },
  workspaces = {
    { name = "Latte", path = constants.latte_root },
  },
  follow_url_func = function(url)
    if is_darwin then
      vim.fn.jobstart({ "open", url })
    end

    if not is_darwin then
      vim.fn.jobstart({ "xdg-open", url })
    end
  end,
})

vim.keymap.set("n", "<Tab>", commands.prompt_for_new_note)
vim.keymap.set("n", "<S-Tab>", pickers.stack_notes)
vim.keymap.set("n", "<Leader><Tab>", pickers.search_all_notes)
vim.keymap.set("n", "<Leader>d", commands.open_daily)
