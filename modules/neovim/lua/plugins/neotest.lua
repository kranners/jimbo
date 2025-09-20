return {
  "nvim-neotest/neotest",
  dependencies = {
    "nvim-neotest/nvim-nio",
    "nvim-lua/plenary.nvim",
    "antoinemadec/FixCursorHold.nvim",
    "nvim-treesitter/nvim-treesitter",
    "marilari88/neotest-vitest",
    "nvim-neotest/neotest-jest",
    -- "thenbe/neotest-playwright",
  },
  config = function()
    require("neotest").setup({
      adapters = {
        require("neotest-vitest")({
          cwd = function()
            return vim.fn.getcwd()
          end,
        }),
        require("neotest-jest")({}),
      },
    })
  end,
  keys = {
    {
      "<Leader>tf",
      function()
        require("neotest").run.run(vim.fn.expand("%"))
      end,
      desc = "Run current test file",
    },
    {
      "<Leader>tt",
      function()
        require("neotest").run.run()
      end,
      desc = "Run nearest test",
    },
  },
}
