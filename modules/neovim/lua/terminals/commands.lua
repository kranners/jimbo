local M = {}

--- @param is_vsplit boolean Whether to open in a vsplit if false will open in a regular split
M.open_terminal = function(is_vsplit)
  local win = vim.api.nvim_get_current_win()
  local buf = vim.api.nvim_create_buf(false, false)

  if is_vsplit then
    vim.cmd("vsplit")
    vim.cmd("wincmd l")
  else
    vim.cmd("split")
    vim.cmd("wincmd j")
  end

  vim.api.nvim_win_set_buf(win, buf)
  vim.fn.jobstart("zsh", { term = true })
  vim.api.nvim_feedkeys("i", "n", false)

  vim.api.nvim_create_autocmd("TermClose", {
    callback = function()
      vim.schedule(function()
        vim.api.nvim_input("<CR>")
        vim.api.nvim_buf_delete(buf, {})
      end)
    end,
    buffer = buf,
  })
end

M.open_terminal_vertical = function()
  M.open_terminal(true)
end

M.open_terminal_horizontal = function()
  M.open_terminal(false)
end

return M
