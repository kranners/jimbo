local NotePreviewer = require("fzf-lua.previewer.builtin").buffer_or_file:extend()

function NotePreviewer:new(o, opts, fzf_win)
  NotePreviewer.super.new(self, o, opts, fzf_win)
  setmetatable(self, NotePreviewer)
  self.filetype = "markdown"

  return self
end

function NotePreviewer:set_preview_buf(newbuf, min_winopts)
  -- This is a complete clone of Base:set_preview_buf
  -- https://github.com/ibhagwan/fzf-lua/blob/ace9968be267b034e450be4feaf6e9107bc34fbd/lua/fzf-lua/previewer/builtin.lua#L144
  -- except it sets the buf filetype and sends autocmds when loading, to
  -- trigger render-markdown

  if not self.win or not self.win:validate_preview() then
    return
  end
  -- Set the preview window to the new buffer
  local curbuf = vim.api.nvim_win_get_buf(self.win.preview_winid)
  if curbuf == newbuf then
    return
  end
  -- Something went terribly wrong
  assert(curbuf ~= newbuf)

  -- CHANGED LINES HERE
  vim.bo[newbuf].filetype = self.filetype
  vim.api.nvim_win_set_buf(self.win.preview_winid, newbuf)
  -- END OF CHANGES

  self.preview_bufnr = newbuf
  -- set preview window options
  if min_winopts then
    -- removes 'number', 'signcolumn', 'cursorline', etc
    self.win:set_style_minimal(self.win.preview_winid)
  else
    -- sets the style defined by `winopts.preview.winopts`
    self:set_style_winopts()
  end
  -- although the buffer has 'bufhidden:wipe' it sometimes doesn't
  -- get wiped when pressing `ctrl-g` too quickly
  self:safe_buf_delete(curbuf)
end

return NotePreviewer
