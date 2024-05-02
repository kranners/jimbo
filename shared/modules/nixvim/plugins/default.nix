{ ... }: {
  imports = [
    ./cmp.nix
    ./conform.nix
    ./lsp.nix
    ./oil.nix
    ./overseer.nix
    ./toggleterm.nix
    ./telescope.nix
    ./focus.nix
    ./lualine.nix
    ./comment.nix
    ./persistence.nix
    ./startify.nix
    ./luasnip.nix
  ];

  programs.nixvim.plugins = {
    notify.enable = true;
    surround.enable = true;
    nvim-autopairs.enable = true;
    rainbow-delimiters.enable = true;
    treesitter.enable = true;
    nvim-lightbulb.enable = true;
    lspsaga.enable = true;
  };
}
