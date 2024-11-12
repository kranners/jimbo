{
  programs.nixvim = {
    plugins.barbar.enable = true;

    keymaps = [
      {
        key = "<C-w>";
        action = "<CMD>BufferCloseAllButVisible<CR>";
        options = { desc = "Clean invisible buffers"; };
        mode = "n";
      }
    ];
  };
}
