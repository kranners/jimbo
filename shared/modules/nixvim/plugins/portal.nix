{pkgs, ...}: let
  portal = pkgs.vimUtils.buildVimPlugin {
    pname = "portal";
    version = "2024-05-04";
    src = pkgs.fetchFromGitHub {
      owner = "cbochs";
      repo = "portal.nvim";
      rev = "77d9d53fec945bfa407d5fd7120f1b4f117450ed";
      sha256 = "sha256-QCdyJ5in3Dm4IVlBUtbGWRZxl87gKHhRiGmZcIGEHm0=";
    };
    meta.homepage = "https://github.com/cbochs/portal.nvim";
  };
in {
  programs.nixvim = {
    extraPlugins = [portal];

    keymaps = [
      {
        action = "<cmd>Portal jumplist backward<cr>";
        key = "<Leader>[";
        mode = "n";
        options = {desc = "Jump backward through jumps";};
      }

      {
        action = "<cmd>Portal jumplist forward<cr>";
        key = "<Leader>]";
        mode = "n";
        options = {desc = "Jump forward through jumps";};
      }
    ];
  };
}
