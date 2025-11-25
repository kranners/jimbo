return {
  "Saghen/blink.cmp",
  dependencies = {
    { "disrupted/blink-cmp-conventional-commits" },
  },
  version = "1.*",
  opts = {
    keymap = {
      preset = "super-tab",
    },
    fuzzy = { implementation = "prefer_rust" },
    completion = {
      menu = {
        draw = {
          columns = {
            {
              "kind_icon",
              "label",
              "label_description",
              "source_name",
              gap = 1,
            },
          },
        },
      },
      documentation = { auto_show = true, auto_show_delay_ms = 0 },
      ghost_text = {
        enabled = true,
      },
    },
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
