{
  programs.nixvim = {
    plugins.neo-tree = {
      enable = true;

      filesystem.filteredItems.hideHidden = false;
      filesystem.filteredItems.visible = true;
    };

    keymaps = [
      {
        action = "<cmd>Neotree toggle left<cr>";
        key = "-";
        mode = "n";
        options = { desc = "Toggle neotree view"; };
      }
    ];
  };
}
