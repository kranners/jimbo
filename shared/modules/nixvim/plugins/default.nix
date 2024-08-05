{ inputs
, pkgs
, ...
}: {
  imports = [
    ./cmp.nix
    ./conform.nix
    ./lsp.nix
    ./oil.nix
    ./overseer.nix
    ./toggleterm.nix
    ./telescope.nix
    ./lualine.nix
    ./comment.nix
    ./persistence.nix
    ./startify.nix
    ./luasnip.nix
    ./treesj.nix
    ./barbar.nix
    ./portal.nix
    ./trouble.nix
    ./goto-preview.nix
    ./neotest.nix
    ./treesitter.nix
    ./obsidian.nix
    ./auto-save.nix
    ./codesnap.nix
    ./zen-mode.nix
    ./spectre.nix
  ];

  programs.nixvim.plugins = {
    notify.enable = true;
    surround.enable = true;
    nvim-autopairs.enable = true;
    rainbow-delimiters.enable = true;
    nvim-lightbulb.enable = true;
    which-key.enable = true;
    noice.enable = true;
    indent-blankline.enable = true;

    mini = {
      enable = true;
      modules = {
        animate = {
          resize.enable = false;
        };
      };
    };
  };

  programs.nixvim = {
    extraPlugins = with inputs.awesome-neovim-plugins.packages.${pkgs.system}; [
      colorful-winsep-nvim
    ];

    extraConfigLua = ''
      require('colorful-winsep').setup()
    '';
  };
}
