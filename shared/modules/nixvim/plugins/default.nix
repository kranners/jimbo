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
  ];

  programs.nixvim.plugins = {
    notify.enable = true;
    surround.enable = true;
    nvim-autopairs.enable = true;
    rainbow-delimiters.enable = true;
    comment.enable = true;
    treesitter.enable = true;
    auto-save.enable = true;
  };
}
