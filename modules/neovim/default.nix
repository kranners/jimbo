{
  sharedHomeModule = { pkgs, ... }: {
    programs.neovim = {
      enable = true;
      defaultEditor = true;
    };

    xdg.configFile = {
      "nvim/init.lua".source = ./init.lua;
      "nvim/lua".source = ./lua;
    };

    home.packages = [
      pkgs.typescript-language-server
      pkgs.vscode-langservers-extracted
      pkgs.emmet-language-server
    ];
  };
}

