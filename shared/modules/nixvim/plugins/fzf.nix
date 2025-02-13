{
  programs.nixvim = {
    plugins.fzf-lua = {
      enable = true;
      profile = "telescope";
    };

    keymaps = [
      {
        key = "]]";
        action = "<CMD>FzfLua lsp_definitions<CR>";
        options = { desc = "Search definitions"; };
        mode = "n";
      }

      {
        key = "[[";
        action = "<CMD>FzfLua lsp_references<CR>";
        options = { desc = "Search references"; };
        mode = "n";
      }

      {
        key = "<C-f>";
        action = "<CMD>FzfLua live_grep formatter=path.filename_first<CR>";
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
        action = "<CMD>FzfLua files formatter=path.filename_first<CR>";
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
        key = "<Leader>q";
        action = "<CMD>FzfLua diagnostics_workspace<CR>";
        options = { desc = "Show diagnostics"; };
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
