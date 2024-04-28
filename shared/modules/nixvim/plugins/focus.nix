{ inputs, pkgs, ... }: {
  programs.nixvim = {
    extraPlugins = with inputs.awesome-neovim-plugins.packages.${pkgs.system}; [ focus-nvim ];

    extraConfigLua = ''
      require('focus').setup()
    '';

    keymaps = [
      {
        key = "<Leader>n";
        action = "<CMD>FocusSplitNicely<CR>";
        options = { desc = "Make a new split"; };
        mode = "n";
      }
    ];
  };
}
