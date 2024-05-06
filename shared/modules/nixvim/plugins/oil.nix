{
  programs.nixvim = {
    keymaps = [
      {
        action = "<cmd>lua require('oil').open()<cr>";
        key = "-";
        mode = "n";
        options = { desc = "View files"; };
      }
    ];

    plugins.oil = {
      enable = true;

      settings.keymaps = {
        "<C-l>" = false;
        "<C-h>" = false;
        "<C-c>" = false;
        "<C-r>" = "actions.refresh";
      };
    };
  };
}
