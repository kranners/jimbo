{
  programs.nixvim = {
    enable = true;

    colorschemes.catppuccin = {
      enable = true;
      settings.flavour = "latte";
    };

    plugins = {
      nix.enable = true;
      surround.enable = true;
      lualine.enable = true;

      lsp.servers = {
        tsserver.enable = true;
        nixd.enable = true;
      };
    };
  };
}
