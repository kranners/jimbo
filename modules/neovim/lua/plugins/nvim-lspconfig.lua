return {
  'neovim/nvim-lspconfig',
  opts = {
    enabled_servers = {
      { name = "yamlls" },
      {
        extraOptions = {
          filetypes = {
            "javascript",
            "javascriptreact",
            "javascript.jsx",
            "typescript",
            "typescriptreact",
            "typescript.tsx",
          },
          init_options = {
            preferences = {
              importModuleSpecifierPreference = "non-relative",
              includeInlayEnumMemberValueHints = true,
              includeInlayFunctionLikeReturnTypeHints = true,
              includeInlayFunctionParameterTypeHints = true,
              includeInlayParameterNameHints = "all",
              includeInlayParameterNameHintsWhenArgumentMatchesName = true,
              includeInlayPropertyDeclarationTypeHints = true,
              includeInlayVariableTypeHints = true,
            },
          },
        },
        name = "ts_ls",
      },
      { name = "terraformls" },
      { name = "ruby_lsp" },
      {
        extraOptions = {
          settings = {
            nixd = {
              formatting = {
                command = { "nixpkgs-fmt" },
              },
            },
          },
        },
        name = "nixd",
      },
      { name = "lua_ls" },
      { name = "jsonls" },
      { name = "html" },
      { name = "gopls" },
      { name = "eslint" },
      { name = "emmet_language_server" },
      { name = "astro" },
      { name = "ruff" },
      { name = "jedi_language_server" },
      {
        extraOptions = {
          settings = {
            basedpyright = {
              typeCheckingMode = "basic",
            },
          },
        },
        name = "basedpyright",
      },
    },
  },
}
