local M = {}

local function replace_current_line_with(str)
  local buffer_number = vim.api.nvim_win_get_buf(0)
  local current_line_number = vim.api.nvim_win_get_cursor(0)[1]

  vim.api.nvim_buf_set_lines(
    buffer_number,
    current_line_number - 1,
    current_line_number,
    false,
    { str }
  )
end

M.cycle_checkbox = function()
  local current_line = vim.api.nvim_get_current_line()

  if current_line:match("^%- %[x%]") then
    local new_line = "- [ ] " .. current_line:sub(7)
    replace_current_line_with(new_line)
    return
  end

  if current_line:match("^%- %[ %]") then
    local new_line = "- [x] " .. current_line:sub(7)
    replace_current_line_with(new_line)
    return
  end

  if current_line:match("^%- ") then
    local new_line = current_line:gsub("- ", "- [ ] ", 1)
    replace_current_line_with(new_line)
    return
  end

  local new_line = string.format("- [ ] %s", current_line)
  replace_current_line_with(new_line)
end

return M
