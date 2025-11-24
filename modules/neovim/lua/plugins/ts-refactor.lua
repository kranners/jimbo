return {
  "kranners/ts-refactor.nvim",
  enabled = false,
  lazy = false,
  name = "ts-refactor",
  dir = "/Users/aaron/git/ts-refactor.nvim",
  dev = {
    fallback = false,
  },
  keys = {
    {
      "<Leader><Leader>",
      function()
        require("ts-refactor").open_action_menu()
      end,
      desc = "Open action menu",
    },
  },
}
