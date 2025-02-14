{ pkgs, inputs, ... }:
let
  flatten = pkgs.vimUtils.buildVimPlugin {
    pname = "flatten";
    version = "2024-05-04";
    src = inputs.flatten;
    meta.homepage = "https://github.com/willothy/flatten.nvim";
  };
in
{
  programs.nixvim = {
    extraPlugins = [ flatten ];
    extraConfigLua = ''
      require("flatten").setup({
        window = {
          open = "split",
        },
      })
    '';
  };
}

