return {
  "Saghen/blink.cmp",
  dependencies = {
    { "disrupted/blink-cmp-conventional-commits" },
  },
  version = "1.*",
  build = "nix run .#build-plugin",
  opts = {
    keymap = {
      preset = "super-tab",
    },
    fuzzy = { implementation = "prefer_rust" },
    sources = {
      default = {
        "conventional_commits", -- add it to the list
        "lsp",
        "buffer",
        "path",
      },
      providers = {
        conventional_commits = {
          name = "Conventional Commits",
          module = "blink-cmp-conventional-commits",
          enabled = function()
            return vim.bo.filetype == "gitcommit"
          end,
          opts = {}, -- none so far
        },
      },
    },
  },
}
