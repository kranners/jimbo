return {
  'neovim/nvim-lspconfig',
  opts = {
    enabled_servers = {
      yamlls = {  },
      ts_ls = {
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
      nixd = {
        settings = {
          nixd = {
            formatting = {
              command = { "nixpkgs-fmt" },
            },
          },
        },
      },
      lua_ls = {  },
      jsonls = {  },
      html = {  },
      eslint = {  },
      emmet_language_server = {  },
      astro = {  },
    },
  },
  config = function(_, opts)
    local build_caps = function()
			local base_caps = vim.lsp.protocol.make_client_capabilities()
			base_caps.general.positionEncodings = { "utf-8" }

			-- if plugin_enabled("blink.cmp") then
			-- 	base_caps = require("blink.cmp").get_lsp_capabilities(base_caps)
			-- end

			return base_caps
		end

    local default_config = {
			capabilities = build_caps(),
			flags = {
				debounce_text_changes = 150,
			},
		}

		for server, config in pairs(opts.enabled_servers) do
			config = vim.tbl_deep_extend("force", default_config, config)

			vim.lsp.config(server, config)
			vim.lsp.enable(server)
		end
  end
}
