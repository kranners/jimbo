{
  programs.nixvim = {
    plugins = {
      zen-mode.enable = true;
      twilight.enable = true;
    };

    keymaps = [
      {
        key = "<Leader>z";
        action = "<CMD>ZenMode<CR>";
        options = { desc = "Toggle zen mode"; };
        mode = "n";
      }

      {
        key = "<C-z>";
        action = "<CMD>Twilight<CR>";
        options = { desc = "Toggle twilight"; };
        mode = "n";
      }
    ];
  };
}
