{ pkgs, inputs, ... }:
let
  toggleterm-manager = pkgs.vimUtils.buildVimPlugin {
    pname = "toggleterm-manager";
    version = "2024-05-04";
    src = inputs.toggleterm-manager;
    meta.homepage = "https://github.com/ryanmsnyder/toggleterm-manager.nvim";
  };
in
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

    extraPlugins = [ toggleterm-manager ];

    keymaps = [
      {
        action = "<cmd>ToggleTerm<cr>";
        key = "=";
        mode = "n";
        options = { desc = "Toggle terminal"; };
      }

      {
        action = "<cmd>Telescope toggleterm_manager<cr>";
        key = "<Leader>=";
        mode = "n";
        options = { desc = "Manage terminals"; };
      }
    ];
  };
}
