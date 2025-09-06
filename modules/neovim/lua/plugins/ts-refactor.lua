return {
  "kranners/ts-refactor.nvim",
  lazy = false,
  name = "ts-refactor",
  dir = "/Users/aaronpierce/workspace/ts-refactor.nvim",
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
