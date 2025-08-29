return {
  'stevearc/conform.nvim',
  opts = {
    format_on_save = { lsp_fallback = true, timeout_ms = 500 },
    formatters_by_fmt = {
      javascript = { { "eslint_d", "prettierd" } },
      javascriptreact = { { "eslint_d", "prettierd" } },
      ruby = { "rubocop" },
      typescript = { { "eslint_d", "prettierd" } },
      typescriptreact = { { "eslint_d", "prettierd" } },
    },
  }
}
