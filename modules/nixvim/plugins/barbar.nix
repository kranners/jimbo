{
  programs.nixvim = {
    plugins.barbar.enable = true;

    keymaps = [
      {
        key = "<Leader>w";
        action = "<CMD>BufferCloseAllButVisible<CR>";
        options = { desc = "Clean invisible buffers"; };
        mode = "n";
      }
    ];
  };
}
