local commands = require("checkboxes.commands")

vim.api.nvim_create_autocmd("filetype", {
  pattern = { "markdown" },
  callback = function(args)
    local buftype = vim.bo[args.buf].buftype
    local filename = vim.api.nvim_buf_get_name(args.buf)

    if buftype ~= "" or filename == "" then
      return
    end

    vim.keymap.set("n", "<CR>", commands.cycle_checkbox, {
      buffer = true,
      noremap = true,
    })
  end,
})
