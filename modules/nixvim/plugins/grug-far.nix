{ pkgs, inputs, ... }:
let
  grug-far = pkgs.vimUtils.buildVimPlugin {
    pname = "grug-far";
    version = "2024-09-13";
    src = inputs.grug-far;
    meta.homepage = "https://github.com/MagicDuck/grug-far.nvim";
  };
in
{
  programs.nixvim = {
    extraPlugins = [ grug-far ];
    extraConfigLua = "require('grug-far').setup()";
    globals.maplocalleader = ",";
    keymaps = [
      {
        key = "<Leader>f";
        action = "<CMD>GrugFar<CR>";
        mode = "n";
        options = { desc = "Open search-replace vertical buffer"; };
      }
    ];
  };
}
