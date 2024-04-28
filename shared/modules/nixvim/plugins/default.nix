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
  ];

  programs.nixvim.plugins = {
    lualine.enable = true;
    notify.enable = true;
    surround.enable = true;
    nvim-autopairs.enable = true;
    rainbow-delimiters.enable = true;
    comment.enable = true;
    treesitter.enable = true;
  };
}
