return {
  "stevearc/conform.nvim",
  opts = {
    format_on_save = { lsp_fallback = false, timeout_ms = 500 },
    formatters_by_ft = {
      ruby = { "rubocop" },
      lua = { "stylua" },
    },
  },
}
