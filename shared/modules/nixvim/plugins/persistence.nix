{
  programs.nixvim = {
    plugins.persistence.enable = true;

    keymaps = [
      {
        key = "<Leader>o";
        action = "<CMD>lua require('persistence').load()<CR>";
        options = { desc = "Load the saved session"; };
        mode = "n";
      }

      {
        key = "<Leader>O";
        action = "<CMD>lua require('persistence').load({ last = true })<CR>";
        options = { desc = "Load the last saved session"; };
        mode = "n";
      }
    ];
  };
}
