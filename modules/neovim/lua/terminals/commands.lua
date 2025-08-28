local M = {}

M.open_terminal_vertical = function()
  local win = vim.api.nvim_get_current_win()
  local buf = vim.api.nvim_create_buf(false, false)

  vim.cmd('vsplit')
  vim.cmd('wincmd l')

  vim.api.nvim_win_set_buf(win, buf)
  vim.fn.jobstart("zsh", { term = true })
  vim.api.nvim_feedkeys("i", "n", false)
end

M.open_terminal_horizontal = function()
  local win = vim.api.nvim_get_current_win()
  local buf = vim.api.nvim_create_buf(false, false)

  vim.cmd('split')
  vim.cmd('wincmd j')

  vim.api.nvim_win_set_buf(win, buf)
  vim.fn.jobstart("zsh", { term = true })
  vim.api.nvim_feedkeys("i", "n", false)
end

return M
