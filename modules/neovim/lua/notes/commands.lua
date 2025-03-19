local constants = require("notes.constants")
local util = require("obsidian.util")

local M = {}

local get_note_template_contents = function(title)
  return {
    "---",
    string.format("id: %s", title),
    string.format('date: "%s"', os.date("%d %B, %Y")),
    "---",
    "",
    string.format("# %s", title),
    "",
  }
end

M.prompt_for_new_note = function()
  local win = vim.api.nvim_get_current_win()

  -- Otherwise, create a new note with a given title
  local title = util.input("Enter title", { completion = "file" })
  if title == "" or title == nil then
    vim.notify("Provide a title for the note")
    return
  end

  -- Open a new horizontal split and move into it
  local buf = vim.api.nvim_create_buf(false, false)
  vim.cmd('split')
  vim.cmd('wincmd j')
  vim.api.nvim_win_set_buf(win, buf)

  -- Open a new note in that buffer
  local new_filepath = string.format("%s/%s.md", constants.stack_root, title)
  vim.cmd.edit(new_filepath)

  -- Append the template to the file
  local template = get_note_template_contents(title)
  vim.api.nvim_put(template, "l", false, true)

  -- Go into insert mode
  vim.api.nvim_feedkeys("i", "t", false)
end

M.open_daily = function()
  -- Open the daily note path
  local daily_note_path = string.format(
    "%s/%s.md",
    constants.latte_root,
    os.date("%Y/%m/%d %B, %Y")
  )

  vim.cmd.edit(daily_note_path)

  -- If we have nothing in there, then add the Daily template.
  local line_count = vim.api.nvim_buf_line_count(0)

  if line_count < 2 then
    local template = get_note_template_contents(os.date("%d %B, %Y"))
    vim.api.nvim_put(template, "l", false, true)

    vim.cmd.read(constants.daily_template_path)
  end
end

return M
