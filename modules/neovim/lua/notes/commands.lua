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

M.prompt_for_new_note_floating = function()
  -- Otherwise, create a new note with a given title
  local title = util.input("Enter title (floating)", { completion = "file" })
  if title == "" or title == nil then
    vim.notify("Provide a title for the note")
    return
  end

  -- Make a new floating window, a new buffer
  local width = math.ceil(math.min(150, vim.o.columns * 0.8))
  local height = math.ceil(math.min(35, vim.o.lines * 0.5))
  local row = math.ceil(vim.o.lines - height) * 0.5 - 1
  local col = math.ceil(vim.o.columns - width) * 0.5 - 1

  local float_config = {
    width = width,
    height = height,
    row = row,
    col = col,
    relative = "editor",
    border = "rounded",
  }

  -- Open the buffer and the window
  local buf = vim.api.nvim_create_buf(false, false)
  vim.api.nvim_open_win(buf, true, float_config)

  -- Open a new note in that buffer
  local new_filepath = string.format("%s/%s.md", constants.stack_root, title)
  vim.cmd.edit(new_filepath)

  -- Append the template to the file
  local template = get_note_template_contents(title)
  vim.api.nvim_put(template, "l", false, true)

  -- Go into insert mode
  vim.api.nvim_feedkeys("i", "t", false)
end

M.prompt_for_new_note_split = function()
  local win = vim.api.nvim_get_current_win()

  -- Otherwise, create a new note with a given title
  local title = util.input("Enter title (split)", { completion = "file" })
  if title == "" or title == nil then
    vim.notify("Provide a title for the note")
    return
  end

  -- Open a new vertical split, stay in the original position
  local buf = vim.api.nvim_create_buf(false, false)
  vim.cmd('vsplit')
  vim.cmd('wincmd l')
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
