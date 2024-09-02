{ inputs
, pkgs
, ...
}: {
  programs.nixvim = {
    extraPlugins = [
      inputs.awesome-neovim-plugins.packages.${pkgs.system}.treesj
    ];

    extraConfigLua = ''
      require('treesj').setup({
      -- Override default keymaps since it overrides <Leader>s
      use_default_keymaps = false,
      -- Stop stopping me from being stupid (default is 120)
      max_join_length = 1200,
      })
    '';

    keymaps = [
      {
        key = "<Leader>j";
        action = "<CMD>TSJJoin<CR>";
        options = { desc = "Join object together"; };
        mode = "n";
      }

      {
        key = "<Leader>k";
        action = "<CMD>TSJSplit<CR>";
        options = { desc = "Split object apart"; };
        mode = "n";
      }

      {
        key = "<Leader>m";
        action = "<CMD>TSJToggle<CR>";
        options = { desc = "Toggle single vs multiline"; };
        mode = "n";
      }
    ];
  };
}
