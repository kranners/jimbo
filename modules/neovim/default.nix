{
  sharedHomeModule = { pkgs, config, ... }:
    let
      inherit (config.lib.file) mkOutOfStoreSymlink;
      nvimSourceHome = "${config.home.homeDirectory}/workspace/jimbo/modules/neovim";
    in
    {
      programs.neovim = {
        enable = true;
        defaultEditor = true;
      };

      xdg.configFile.nvim.source = mkOutOfStoreSymlink nvimSourceHome;

      home.packages = [
        pkgs.typescript-language-server
        pkgs.vscode-langservers-extracted
        pkgs.emmet-language-server
        pkgs.nixd
        pkgs.nixpkgs-fmt
        pkgs.ruff
        pkgs.python313Packages.jedi-language-server
        pkgs.fzf
        pkgs.lua-language-server
        pkgs.gh
      ];
    };
}

