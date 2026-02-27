return {
  "rachartier/tiny-code-action.nvim",
  dependencies = {
    { "nvim-lua/plenary.nvim" },
    { "ibhagwan/fzf-lua" },
  },
  event = "LspAttach",
  opts = {},
  keys = {
    {
      "<Leader><CR>",
      function()
        require("tiny-code-action").code_action()
      end,
      desc = "Show code actions",
    },
  },
}
