{ pkgs, inputs, ... }:
let
  dial = pkgs.vimUtils.buildVimPlugin {
    pname = "dial";
    version = "2024-12-01";
    src = inputs.dial;
    meta.homepage = "https://github.com/monaqa/dial.nvim";
  };
in
{
  programs.nixvim = {
    extraPlugins = [ dial ];

    extraConfigLua = builtins.readFile ./dial.lua;

    keymaps = [
      {
        key = "<C-a>";
        mode = "n";
        action.__raw = ''function() require("dial.map").manipulate("increment", "normal") end'';
        options.desc = "Increment with dial";
      }

      {
        key = "<C-x>";
        mode = "n";
        action.__raw = ''function() require("dial.map").manipulate("decrement", "normal") end'';
        options.desc = "Decrement with dial";
      }

      {
        key = "<C-a>";
        mode = "v";
        action.__raw = ''function() require("dial.map").manipulate("increment", "visual") end'';
        options.desc = "Increment selection with dial";
      }

      {
        key = "<C-x>";
        mode = "v";
        action.__raw = ''function() require("dial.map").manipulate("decrement", "visual") end'';
        options.desc = "Decrement selection with dial";
      }
    ];
  };
}
