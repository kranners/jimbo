{
  programs.nixvim = {
    plugins.zen-mode.enable = true;

    keymaps = [
      {
        key = "<Leader>z";
        action = "<CMD>ZenMode<CR>";
        options = { desc = "Toggle zen mode"; };
        mode = "n";
      }
    ];
  };
}
