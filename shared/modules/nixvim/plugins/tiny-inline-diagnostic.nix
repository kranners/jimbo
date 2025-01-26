{ pkgs, inputs, ... }:
let
  tiny-inline-diagnostic = pkgs.vimUtils.buildVimPlugin {
    pname = "tiny-inline-diagnostic";
    version = "2024-11-06";
    src = inputs.tiny-inline-diagnostic;
    meta.homepage = "https://github.com/rachartier/tiny-inline-diagnostic.nvim";
  };
in
{
  programs.nixvim = {
    diagnostics = {
      virtual_text = false;
    };

    extraPlugins = [ tiny-inline-diagnostic ];
    extraConfigLua = ''
      require('tiny-inline-diagnostic').setup({
        preset = "ghost",

        options = {
          multiline = {
            enabled = true,
            always_show = true,
          },
        },
      })
    '';
  };
}
