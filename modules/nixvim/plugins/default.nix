{
  sharedSystemModule = {
    imports = [
      ./conform.nix
      ./lsp.nix
      ./oil.nix
      ./overseer.nix
      ./toggleterm.nix
      ./comment.nix
      ./treesj.nix
      ./barbar.nix
      ./treesitter.nix
      ./obsidian.nix
      ./codesnap.nix
      ./resession.nix
      ./flatten.nix
      ./noice.nix
      ./grug-far.nix
      ./zen-mode.nix
      ./fzf.nix
      ./fugitive.nix
      ./tiny-inline-diagnostic.nix
      ./markdown.nix
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
  };
}
