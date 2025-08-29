return {
  'stevearc/overseer.nvim',
  opts = {
    strategy = "terminal",
    task_list = {
      direction = "bottom",
      bindings = {
        ["<C-h>"] = "<CMD>wincmd h<CR>",
        ["<C-j>"] = "<CMD>wincmd j<CR>",
        ["<C-k>"] = "<CMD>wincmd k<CR>",
        ["<C-l>"] = "<CMD>wincmd l<CR>",
      },
    },
  },
}
