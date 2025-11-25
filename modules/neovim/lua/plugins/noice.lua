return {
  "folke/noice.nvim",
  opts = {
    health = { checker = false },
    routes = { { filter = { event = "msg_showmode" }, view = "notify" } },
    views = {
      cmdline_popup = {
        win_options = {
          winhighlight = "NormalFloat:NormalFloat,FloatBorder:FloatBorder",
        },
      },
    },
  },
}
