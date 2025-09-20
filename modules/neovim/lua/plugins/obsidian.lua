return {
  "epwalsh/obsidian.nvim",
  dependencies = {
    "nvim-lua/plenary.nvim",
  },
  ft = "markdown",
  opts = {
    workspaces = {
      {
        name = "Latte",
        path = "~/Documents/Latte",
      },
    },
    ui = {
      enable = false,
    },
  },
}
