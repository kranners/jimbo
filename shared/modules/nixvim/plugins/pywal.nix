{ pkgs, ... }:
let
  neo-pywal = pkgs.vimUtils.buildVimPlugin {
    pname = "neopywal.nvim";
    version = "2024-06-22";
    src = pkgs.fetchFromGitHub {
      owner = "RedsXDD";
      repo = "neopywal.nvim";
      rev = "27ba34947c101779f8ed96c5b5f32b78e7b804bc";
      hash = "sha256-+11WVHBaRUj2tMMUO5vXl0Jy8nj6Y5i/+m9+rcOeKzY=";
    };
    meta.homepage = "https://github.com/RedsXDD/neopywal.nvim";
  };
in
{
  programs.nixvim = {
    extraPlugins = [ neo-pywal ];

    extraConfigLua = ''
      require("neopywal").setup()
      vim.cmd.colorscheme("neopywal")
    '';

    keymaps = [
      {
        key = "<Leader>z";
        action = "<CMD>lua require('neopywal').load()<CR>";
        options = { desc = "Reload colorscheme"; };
        mode = "n";
      }
    ];
  };
}
