{ pkgs, ... }:
let
  toggleterm-manager = pkgs.vimUtils.buildVimPlugin {
    pname = "toggleterm-manager";
    version = "2024-05-04";
    src = pkgs.fetchFromGitHub {
      owner = "ryanmsnyder";
      repo = "toggleterm-manager.nvim";
      rev = "31318b85a7cc20bf50ce32aedf4e835844133863";
      sha256 = "sha256-7t61kcqeOS9hPXc9y88Sa8D0ZXIqxCXtxFQzmHKFJ8c=";
    };
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
      };

      extraOptions.hide_numbers = false;
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
