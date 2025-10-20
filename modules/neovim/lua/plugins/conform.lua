return {
  "stevearc/conform.nvim",
  opts = {
    format_on_save = {
      -- lsp_fallback = false,
      timeout_ms = 500,
      lsp_format = "first",
      filter = function(client)
        return client.name == "eslint"
      end,
    },
    formatters_by_ft = {
      ruby = { "rubocop" },
      lua = { "stylua" },
    },
  },
}
