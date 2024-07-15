{ pkgs, ... }: {
  programs.nixvim.plugins.spectre = {
    enable = true;

    package = pkgs.vimPlugins.nvim-spectre.overrideAttrs (old: {
      src = pkgs.fetchFromGitHub {
        owner = "nvim-pack";
        repo = "nvim-spectre";
        rev = "9a28f926d3371b7ef02243cbbb653a0478d06e31";
        hash = "sha256-Y8iHDlnv/zUbkaFqT2+DpMGyrrzZAhgyYfl7iPw625Q=";
      };
    });

    findPackage = pkgs.ripgrep;
    replacePackage = pkgs.gnused;
  };
}
