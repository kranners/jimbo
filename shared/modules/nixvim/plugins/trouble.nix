{
  programs.nixvim = {
    plugins.trouble.enable = true;

    keymaps = [
      {
        key = "<Leader>q";
        action = "<CMD>Trouble diagnostics<CR>";
        options = { desc = "Toggle view all issues"; };
        mode = "n";
      }
    ];
  };
}
