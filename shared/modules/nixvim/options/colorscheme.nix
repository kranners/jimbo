{ pkgs, ... }:
let
  github-nvim = pkgs.vimUtils.buildVimPlugin {
    name = "github-nvim-theme";
    src = pkgs.fetchFromGitHub {
      owner = "projekt0n";
      repo = "github-nvim-theme";
      rev = "d832925e77cef27b16011a8dfd8835f49bdcd055";
      hash = "sha256-vsIr3UrnajxixDo0cp+6GoQfmO0KDkPX8jw1e0fPHo4=";
    };
  };
in
{
  programs.nixvim = {
    extraPlugins = with pkgs.vimPlugins; [
      onedarkpro-nvim
      github-nvim
    ];

    colorscheme = "onedark_vivid";
    opts.termguicolors = true;
  };
}
