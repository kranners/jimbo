{ pkgs, ... }: {
  focus-nvim = pkgs.vimUtils.buildVimPlugin {
    pname = "focus.nvim";
    version = "c9bc6";

    src = pkgs.fetchFromGitHub {
      owner = "nvim-focus";
      repo = "focus.nvim";
      rev = "c9bc6a969c3ff0d682f389129961c9e71ff2c918";
      sha256 = "19r8gslq4m70rgi51bnlazhppggiy3crnmaqyvjc25f59f1213a7";
    };
  };
}  
