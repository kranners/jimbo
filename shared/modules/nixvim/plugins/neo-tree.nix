{
  programs.nixvim = {
    plugins.neo-tree = {
      enable = true;

      filesystem.filteredItems = {
        hideHidden = false;
        visible = true;
      };

      eventHandlers = {
        neo_tree_buffer_enter = ''
          function()
            vim.opt.relativenumber = true
            vim.opt.number = true
          end
        '';
      };
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
