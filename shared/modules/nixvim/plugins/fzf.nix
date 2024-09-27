{ pkgs, inputs, ... }:
let
  fzf-lua-resession = pkgs.vimUtils.buildVimPlugin {
    pname = "fzf-lua-resession";
    version = "2024-09-26";
    src = inputs.fzf-lua-resession;
    meta.homepage = "https://github.com/roastedramen/fzf-lua-resession.nvim";
  };
in
{
  programs.nixvim = {
    plugins.fzf-lua = {
      enable = true;
      profile = "telescope";
    };

    extraPlugins = [ fzf-lua-resession ];
    extraConfigLua = ''
      require("fzf-lua-resession").setup({
        session_dir = "dirsession"
      })

      vim.keymap.set(
        "n", "<Leader>L",
        function()
          require('fzf-lua').resession_picker()
        end, 
        { desc = "Resession picker" }
      )
    '';

    keymaps = [
      {
        key = "<C-f>";
        action = "<CMD>FzfLua live_grep<CR>";
        options = { desc = "Fuzzy find file contents"; };
        mode = "n";
      }

      {
        key = "<C-b>";
        action = "<CMD>FzfLua buffers<CR>";
        options = { desc = "Search through current buffers"; };
        mode = "n";
      }

      {
        key = "<C-o>";
        action = "<CMD>FzfLua files<CR>";
        options = { desc = "Find files by name"; };
        mode = "n";
      }

      {
        key = "<Leader>b";
        action = "<CMD>FzfLua buffers<CR>";
        options = { desc = "Find buffers"; };
        mode = "n";
      }

      {
        key = "<C-p>";
        action = "<CMD>FzfLua keymaps<CR>";
        options = { desc = "Show keymaps / command prompt"; };
        mode = "n";
      }

      {
        key = "<Leader>gs";
        action = "<CMD>FzfLua git_status<CR>";
        options = { desc = "Show git status"; };
        mode = "n";
      }

      {
        key = "<Leader>gb";
        action = "<CMD>FzfLua git_branches<CR>";
        options = { desc = "List git branches"; };
        mode = "n";
      }
    ];
  };
}
