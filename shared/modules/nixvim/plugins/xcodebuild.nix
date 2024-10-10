{ pkgs, inputs, ... }:
let
  xcodebuild = pkgs.vimUtils.buildVimPlugin {
    pname = "xcodebuild";
    version = "2024-10-10";
    src = inputs.xcodebuild;
    meta.homepage = "https://github.com/wojciech-kulik/xcodebuild.nvim";
  };
in
{
  programs.nixvim = {
    extraPlugins = [ xcodebuild ];
    extraConfigLua = "require('xcodebuild').setup()";

    keymaps = [
      {
        key = "<Leader>x";
        action = "<CMD>XcodebuildPicker<CR>";
        options = { desc = "Show Xcodebuild actions"; };
        mode = "n";
      }
    ];
  };
}
