{
  programs.nixvim = {
    plugins.lsp = {
      enable = true;
      inlayHints = false;

      servers = {
        astro.enable = true;
        jsonls.enable = true;
        html.enable = true;
        eslint.enable = true;
        pyright.enable = true;
        yamlls.enable = true;
        lua_ls.enable = true;
        ruby_lsp.enable = true;
        gopls.enable = true;
        emmet_language_server.enable = true;
        terraformls.enable = true;
        ts_ls = {
          enable = true;

          extraOptions = {
            init_options = {
              preferences = {
                includeInlayParameterNameHints = "all";
                includeInlayParameterNameHintsWhenArgumentMatchesName = true;
                includeInlayFunctionParameterTypeHints = true;
                includeInlayVariableTypeHints = true;
                includeInlayPropertyDeclarationTypeHints = true;
                includeInlayFunctionLikeReturnTypeHints = true;
                includeInlayEnumMemberValueHints = true;
                importModuleSpecifierPreference = "non-relative";
              };
            };
          };
        };

        nixd = {
          enable = true;
          settings.formatting.command = [ "nixpkgs-fmt" ];
        };
      };
    };

    keymaps = [
      {
        key = "<CR>";
        action = "<CMD>lua vim.lsp.buf.hover()<CR>";
        options = { desc = "Hover over token"; };
        mode = "n";
      }

      {
        key = "<Leader><CR>";
        action = "<CMD>lua vim.lsp.buf.code_action()<CR>";
        options = { desc = "Show code actions"; };
        mode = "n";
      }

      {
        key = "<Leader>r";
        action = "<CMD>lua vim.lsp.buf.rename()<CR>";
        options = { desc = "Rename symbol"; };
        mode = "n";
      }
    ];
  };
}
