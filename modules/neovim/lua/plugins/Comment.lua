return {
  'numToStr/Comment.nvim',
  opts = {
    mappings = { basic = false, extra = false }
  },
  keys = {
    {
      "<C-/>",
      "<CMD>lua require('Comment.api').toggle.linewise.current()<CR><C-o>$",
      mode = "i",
      desc = "Toggle comment on current line (insert mode)",
    },
    {
      "<C-/>",
      "<PLUG>(comment_toggle_linewise_current)",
      mode = "n",
      desc = "Toggle comment (normal)",
    },
    {
      "<C-/>",
      "<PLUG>(comment_toggle_linewise_visual)",
      mode = "x",
      desc = "Toggle comment (visual)",
    },
  }
}
