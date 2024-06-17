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

      settings = {
        default_file_explorer = true;
        delete_to_trash = true;
        skip_confirm_for_simple_edits = true;

        view_options = {
          show_hidden = true;
          natural_order = true;
        };

        win_options.wrap = true;

        keymaps = {
          "<C-l>" = false;
          "<C-h>" = false;
          "<C-c>" = false;
          "<C-r>" = "actions.refresh";
        };
      };
    };
  };
}
