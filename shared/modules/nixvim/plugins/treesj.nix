{ inputs, pkgs, ... }: {
  programs.nixvim = {
    extraPlugins = with inputs.awesome-neovim-plugins.packages.${pkgs.system}; [
      treesj
    ];

    extraConfigLua = ''
      require('treesj').setup()
    '';

    keymaps = [
      {
        key = "J";
        action = "<CMD>TSJJoin<CR>";
        options = { desc = "Join line with TreeSJ"; };
        mode = "n";
      }

      {
        key = "K";
        action = "<CMD>TSJSplit<CR>";
        options = { desc = "Split line with TreeSJ"; };
        mode = "n";
      }
    ];
  };
}
