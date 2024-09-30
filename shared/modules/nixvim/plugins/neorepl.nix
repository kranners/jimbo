{ pkgs, inputs, ... }:
let
  neorepl = pkgs.vimUtils.buildVimPlugin {
    pname = "neorepl";
    version = "2024-09-28";
    src = inputs.neorepl;
    meta.homepage = "https://github.com/ii14/neorepl.nvim";
  };
in
{
  programs.nixvim = {
    extraPlugins = [ neorepl ];
  };
}
