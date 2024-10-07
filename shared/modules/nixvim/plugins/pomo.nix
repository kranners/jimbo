{ pkgs, inputs, ... }:
let
  pomo = pkgs.vimUtils.buildVimPlugin {
    pname = "pomo";
    version = "2024-10-07";
    src = inputs.pomo;
    meta.homepage = "https://github.com/epwalsh/pomo.nvim";
  };
in
{
  programs.nixvim = {
    extraPlugins = [ pomo ];
    extraConfigLua = ''
      require("pomo").setup({
        sessions = {
          pomodoro = {
            { name = "Work", duration = "25m" },
            { name = "Short Break", duration = "5m" },
            { name = "Work", duration = "25m" },
            { name = "Short Break", duration = "5m" },
            { name = "Work", duration = "25m" },
            { name = "Long Break", duration = "15m" },
          },
        },
      })
    '';

    keymaps = [
      {
        key = "<Leader>p";
        action = "<CMD>TimerSession pomodoro<CR>";
        mode = "n";
        options = { desc = "Start pomodoro session"; };
      }
    ];
  };
}
