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
      action = "<CMD>lua require('Comment.api').toggle.linewise() <CR>";
      options = { desc = "Toggle current line comment (linewise)"; };
      mode = [ "n" "i" ];
    }

    {
      key = "<C-\\>";
      action = "<CMD>lua require('Comment.api').toggle.blockwise() <CR>";
      options = { desc = "Toggle current line comment (blockwise)"; };
      mode = [ "n" "i" ];
    }
  ];
}

# -- Toggle current line (linewise) using C-/
# vim.keymap.set ('n', '<C-_>', api.toggle.linewise.current)
#
# -- Toggle current line (blockwise) using C-\
# vim.keymap.set('n', '<C-\\>', api.toggle.blockwise.current)



