return {
  'nvim-lualine/lualine.nvim',
  opts = {
    sections = {
      lualine_x = {
        {
          function()
            local mode = require("noice").api.statusline.mode
            if mode.has() then
              local content = mode.get()
              if string.match(content, "^recording @%w$") then
                return content
              end
            end
            return ""
          end,
          color = { fg = "#ff9e64" },
        },
      },
    },
  },
}
