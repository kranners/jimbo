{
  programs.nixvim = {
    plugins.toggleterm.enable = true;

    keymaps = [
      {
        action = "<cmd>ToggleTerm direction=float<cr>";
        key = "=";
        mode = "n";
        options = { desc = "Toggle terminal"; };
      }
    ];
  };
}
