{
  programs.nixvim.plugins.comment = {
    enable = true;
    settings = {
      mappings = {
        basic = false;
        extra = false;
      };
    };
  };

  programs.nixvim.keymaps = [
    {
      key = "<C-/>";
      action = "<CMD>lua require('Comment.api').toggle.linewise.current<CR>";
      options = { desc = "Toggle comment on current line (insert mode) "; };
      mode = "i";
    }

    {
      key = "<C-/>";
      action = "<PLUG>(comment_toggle_linewise_current)";
      options = { desc = "Toggle comment (normal)"; };
      mode = "n";
    }

    {
      key = "<C-/>";
      action = "<PLUG>(comment_toggle_linewise_visual)";
      options = { desc = "Toggle comment (visual)"; };
      mode = "x";
    }
  ];
}
