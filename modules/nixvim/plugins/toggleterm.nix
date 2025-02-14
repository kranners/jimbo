{
  programs.nixvim = {
    plugins.toggleterm = {
      enable = true;
      settings = {
        direction = "vertical";
        size = 60;
        hide_numbers = false;
      };
    };

    keymaps = [
      {
        action = "<cmd>ToggleTerm<cr>";
        key = "=";
        mode = "n";
        options = { desc = "Toggle terminal"; };
      }
    ];
  };
}
