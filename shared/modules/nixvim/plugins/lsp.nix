{
  programs.nixvim = {
    plugins.lsp = {
      enable = true;
      servers = {
        astro.enable = true;
        tsserver.enable = true;
        lua-ls.enable = true;
        jsonls.enable = true;
        html.enable = true;
        # FIXME: Remove this when not working with cooked ESLint
        # eslint.enable = true;
        pyright.enable = true;
        yamlls.enable = true;

        nixd = {
          enable = true;
          settings.formatting.command = [ "nixpkgs-fmt" ];
        };
      };
    };

    keymaps = [
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
