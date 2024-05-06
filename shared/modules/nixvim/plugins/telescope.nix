{
  programs.nixvim = {
    plugins.telescope = {
      enable = true;
      extensions = {
        fzf-native.enable = true;
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
		prompt_position = "top";
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
	    file_ignore_patterns = [ "node_modules" ];
	    path_display = [ "truncate" ];
	    winblend = 0;
	    border = {};
	    borderchars = [ "─" "│" "─" "│" "╭" "╮" "╯" "╰" ];
	    color_devicons = true;
	  };
      };
    };

    keymaps = [
      {
        key = "<C-f>";
        action = "<CMD>Telescope live_grep<CR>";
        options = {desc = "Fuzzy find file contents";};
        mode = "n";
      }

      {
        key = "<C-o>";
        action = "<CMD>Telescope find_files<CR>";
        options = {desc = "Find files by name";};
        mode = "n";
      }
    ];
  };
}
