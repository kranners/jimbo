{ pkgs, inputs, ... }:
let
  remote-line = pkgs.vimUtils.buildVimPlugin {
    pname = "remote-line";
    version = "2024-10-17";
    src = inputs.remote-line;
    meta.homepage = "https://github.com/ksaito422/remote-line.nvim";

  };
in
{
  programs.nixvim = {
    extraPlugins = [ remote-line ];
    extraConfigLua = "require('remote-line').setup()";
    keymaps = [
      {
        key = "<C-m>";
        action = "<CMD>RemoteLine<CR>";
        options = { desc = "Open position in remote"; };
        mode = "n";
      }
    ];

  };
}
