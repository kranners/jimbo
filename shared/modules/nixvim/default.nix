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
      { key = "<ESC>"; action = "<C-\\><C-n>"; options = { desc = "Let me move"; }; mode = "t"; }
      { key = "<Leader>s"; action = "<CMD>wa<CR>"; options = { desc = "Save all"; }; mode = "n"; }

      { key = "<Leader><CR>"; action = "<CMD>lua vim.lsp.buf.code_action()<CR>"; options = { desc = "Show code actions"; }; mode = "n"; }

      { key = "<C-h>"; action = "<CMD>wincmd h <CR>"; options = { desc = "Focus window left"; }; mode = [ "t" "n" "i" ]; }
      { key = "<C-j>"; action = "<CMD>wincmd j <CR>"; options = { desc = "Focus window down"; }; mode = [ "t" "n" "i" ]; }
      { key = "<C-k>"; action = "<CMD>wincmd k <CR>"; options = { desc = "Focus window up"; }; mode = [ "t" "n" "i" ]; }
      { key = "<C-l>"; action = "<CMD>wincmd l <CR>"; options = { desc = "Focus window right"; }; mode = [ "t" "n" "i" ]; }

      { key = "<Left>"; action = "<CMD>vertical resize +1<CR>"; options = { desc = "Grow window left"; }; mode = "n"; }
      { key = "<Down>"; action = "<CMD>resize +1<CR>"; options = { desc = "Grow window down"; }; mode = "n"; }
      { key = "<Up>"; action = "<CMD>resize -1<CR>"; options = { desc = "Shrink window up"; }; mode = "n"; }
      { key = "<Right>"; action = "<CMD>vertical resize -1<CR>"; options = { desc = "Shrink window left"; }; mode = "n"; }

      { key = "<ESC>"; action = "<CMD>nohlsearch<Bar>:echo<CR>"; options = { desc = "Cancel search"; }; mode = "n"; }

      { key = "<C-t>"; action = "<CMD>tabnew<CR>"; options = { desc = "New tab"; }; mode = "n"; }
      { key = "<C-tab>"; action = "<CMD>tabnext<CR>"; options = { desc = "Next tab"; }; mode = "n"; }
      { key = "<C-s-tab>"; action = "<CMD>tabprevious<CR>"; options = { desc = "Previous tab"; }; mode = "n"; }
    ];
  };
}
