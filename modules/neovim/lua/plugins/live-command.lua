return {
  "smjonas/live-command.nvim",
  opts = {
    commands = {
      Norm = { cmd = "norm" },
    },
  },
  config = function(_, opts)
    require("live-command").setup(opts)

    vim.cmd("cnoreabbrev norm Norm")
  end,
}
