{
  programs.nixvim = {
    plugins.telescope = {
      enable = true;

      extensions = {
        fzf-native.enable = true;
        frecency.enable = true;
        media-files.enable = true;
      };

      settings = {
        pickers.find_files = {
          hidden = true;
        };

        defaults = {
          prompt_prefix = " 🔎  ";
          selection_caret = "  ";
          entry_prefix = "  ";
          initial_mode = "insert";
          selection_strategy = "reset";
          sorting_strategy = "ascending";
          layout_strategy = "horizontal";
          layout_config = {
            horizontal = {
              preview_width = 0.55;
              results_width = 0.8;
            };
            vertical = {
              mirror = false;
            };
            width = 0.87;
            height = 0.80;
            preview_cutoff = 120;
          };
          file_ignore_patterns = [ "node_modules" ".git/" ".cache" "dist/" ];
          path_display = [ "truncate" ];
          winblend = 0;
          border = { };
          borderchars = [ "─" "│" "─" "│" "╭" "╮" "╯" "╰" ];
          color_devicons = true;
        };
      };
    };
  };
}
