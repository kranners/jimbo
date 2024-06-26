{
  programs.nixvim = {
    plugins.flash = {
      enable = true;
      modes.char = {
        jumpLabels = true;
        multiLine = false;
      };
    };

    keymaps = [
      {
        key = "<Leader>v";
        action = "<CMD>lua require('flash').treesitter()<CR>";
        options = { desc = "Select by treesitter node"; };
        mode = "n";
      }
    ];
  };
}
