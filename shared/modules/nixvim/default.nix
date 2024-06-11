{ config
, pkgs
, lib
, inputs
, ...
}: {
  imports = [
    ./options
    ./plugins
  ];

  programs.nixvim = {
    enable = true;

    globals.mapleader = " ";

    keymaps = [
      {
        key = "<ESC><ESC>";
        action = "<C-\\><C-n>";
        options = { desc = "Move into normal mode in a terminal buffer"; };
        mode = "t";
      }

      {
        key = "<ESC>";
        action = "<CMD>nohlsearch<Bar>:echo<CR><CMD>lua require('goto-preview').close_all_win({ skip_curr_window = true })<CR>";
        options = { desc = "Cancel search"; };
        mode = "n";
      }

      {
        key = "<Leader>s";
        action = "<CMD>wa<CR>";
        options = { desc = "Save all"; };
        mode = "n";
      }

      {
        key = "<C-[>";
        action = "<C-o>";
        options = { desc = "Jump back to last entry in jumplist"; };
        mode = "n";
      }
    ];
  };
}
