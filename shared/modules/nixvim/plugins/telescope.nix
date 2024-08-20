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

    keymaps = [
      {
        key = "<C-f>";
        action = "<CMD>Telescope live_grep<CR>";
        options = { desc = "Fuzzy find file contents"; };
        mode = "n";
      }

      {
        key = "<C-o>";
        action = "<CMD>Telescope find_files<CR>";
        options = { desc = "Find files by name"; };
        mode = "n";
      }

      {
        key = "<Leader>}";
        action = "<CMD>Telescope lsp_references<CR>";
        options = { desc = "Find references of token"; };
        mode = "n";
      }

      {
        key = "<Leader>{";
        action = "<CMD>Telescope lsp_definitions<CR>";
        options = { desc = "Find definitions of token"; };
        mode = "n";
      }

      {
        key = "<Leader>p";
        action = "<CMD>Telescope keymaps<CR>";
        options = { desc = "Show keymaps / command prompt"; };
        mode = "n";
      }

      {
        key = "<Leader>gs";
        action = "<CMD>Telescope git_status<CR>";
        options = { desc = "Show keymaps / command prompt"; };
        mode = "n";
      }

      {
        key = "<Leader>gb";
        action = "<CMD>Telescope git_branches<CR>";
        options = { desc = "Show keymaps / command prompt"; };
        mode = "n";
      }
    ];
  };
}
