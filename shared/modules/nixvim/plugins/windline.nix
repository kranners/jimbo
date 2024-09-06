{ pkgs, inputs, ... }:
let
  windline = pkgs.vimUtils.buildVimPlugin {
    pname = "windline";
    version = "2024-09-06";
    src = inputs.windline;
    meta.homepage = "https://github.com/windwp/windline.nvim";
  };
in
{
  programs.nixvim = {
    extraPlugins = [ windline ];
    extraConfigLua = "require('wlsample.vscode')";
  };
}
