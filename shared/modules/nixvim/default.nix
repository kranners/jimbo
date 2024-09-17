{ lib, ... }:
let
  esc-actions = [
    "<CMD>nohlsearch<Bar>:echo<CR>"
    "<CMD>lua require('goto-preview').close_all_win({ skip_curr_window = true })<CR>"
  ];
in
{
  imports = [
    ./options
    ./plugins
  ];

  programs.nixvim = {
    enable = true;

    globals.mapleader = " ";

    keymaps = [
      {
        key = "<ESC>";
        action = "<C-\\><C-n>";
        options = { desc = "Move into normal mode in a terminal buffer"; };
        mode = "t";
      }

      {
        key = "<ESC>";
        action = lib.strings.concatStrings esc-actions;
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

      {
        key = "<C-]>";
        action = "<C-i>";
        options = { desc = "Jump forward to next entry in jumplist"; };
        mode = "n";
      }

      {
        key = "\"\"";
        action = "<CMD>Telescope registers<CR>";
        options = { desc = "View the registers"; };
        mode = "n";
      }
    ];
  };
}
