{
  programs.nixvim = {
    plugins.typescript-tools.enable = true;

    plugins.lsp = {
      enable = true;
      servers = {
        astro.enable = true;
        tsserver.enable = true;
        lua-ls.enable = true;
        jsonls.enable = true;
        html.enable = true;
        eslint.enable = true;
        pyright.enable = true;
        yamlls.enable = true;

        nixd = {
          enable = true;
          settings.formatting.command = "nixpkgs-fmt";
        };
      };
    };

    keymaps = [
      {
        key = "<Leader><Leader>";
        action = "<CMD>EslintFixAll<CR>";
        options = { desc = "Fix all available"; };
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
