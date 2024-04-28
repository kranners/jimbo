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
        eslint.enable = true;
        pyright.enable = true;
        yamlls.enable = true;
      };
    };

    plugins.lsp.servers.nixd = {
      enable = true;
      settings.formatting.command = "nixpkgs-fmt";
    };
  };
}
