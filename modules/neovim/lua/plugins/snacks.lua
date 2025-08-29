return {
  'folke/snacks.nvim',
  opts = {
    picker = {
      main = {
        file = false,
        current = true,
      },
      formatters = {
        file = {
          filename_first = false,
          truncate = 10000,
        },
      },
    },
  },
}
