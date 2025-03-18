{ pkgs, inputs, ... }:
let
  eagle = pkgs.vimUtils.buildVimPlugin {
    pname = "eagle";
    version = "2025-03-18";
    src = inputs.eagle;
    meta.homepage = "https://github.com/soulis-1256/eagle.nvim";
  };
in
{
  programs.nixvim = {
    extraPlugins = [ eagle ];
    extraConfigLua = ''
      require('eagle').setup({
        keyboard_mode = true,
      })
    '';

    keymaps = [
      {
        key = "<CR>";
        action = "<CMD>EagleWin<CR>";
        mode = "n";
        options = {
          desc = "Open Eagle hover window 🦅";
          silent = true;
        };
      }
    ];
  };
}
