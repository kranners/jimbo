{
  programs.nixvim = {
    plugins.toggleterm = {
      enable = true;
      settings = {
        direction = "float";
        size = 40;
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
