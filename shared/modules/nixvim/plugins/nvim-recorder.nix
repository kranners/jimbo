{ pkgs, inputs, ... }:
let
  nvim-recorder = pkgs.vimUtils.buildVimPlugin {
    pname = "nvim-recorder";
    version = "2025-01-08";
    src = inputs.nvim-recorder;
    meta.homepage = "https://github.com/chrisgrieser/nvim-recorder";
  };
in
{
  programs.nixvim = {
    extraPlugins = [ nvim-recorder ];
    extraConfigLua = "require('recorder').setup({})";
  };
}
