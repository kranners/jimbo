{
  imports = [
    ./cmp.nix
    ./conform.nix
    ./lsp.nix
    ./oil.nix
    ./overseer.nix
    ./toggleterm.nix
    ./telescope.nix
    ./comment.nix
    ./luasnip.nix
    ./treesj.nix
    ./barbar.nix
    ./trouble.nix
    ./neotest.nix
    ./treesitter.nix
    ./obsidian.nix
    ./codesnap.nix
    ./resession.nix
    ./windline.nix
    ./flatten.nix
    ./noice.nix
    ./grug-far.nix
    ./zen-mode.nix
    ./fzf.nix
    ./fugitive.nix
    ./tiny-inline-diagnostic.nix
    ./dial.nix
    ./nvim-recorder.nix
  ];

  programs.nixvim.plugins = {
    vim-surround.enable = true;
    nvim-autopairs.enable = true;
    rainbow-delimiters.enable = true;
    nvim-lightbulb.enable = true;
    which-key.enable = true;
    indent-blankline.enable = true;
    gitsigns.enable = true;
    neoscroll.enable = true;
    web-devicons.enable = true;
  };
}
