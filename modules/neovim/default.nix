{
  sharedHomeModule = { pkgs, config, lib, ... }:
    let
      inherit (config.lib.file) mkOutOfStoreSymlink;
      inherit (lib) fileContents;

      nvimLuaSourceHome = "${config.home.homeDirectory}/workspace/jimbo/modules/neovim/lua";
      nvimAfterSourceHome = "${config.home.homeDirectory}/workspace/jimbo/modules/neovim/after";
      nvimLazyLockSourceHome = "${config.home.homeDirectory}/workspace/jimbo/modules/neovim/lazy-lock.json";
    in
    {
      programs.neovim = {
        enable = true;
        defaultEditor = true;

        # Adapting to new behaviour introduced in stateVersion 26.05
        withRuby = false;
        withPython3 = false;

        # init.lua needs to be passed in as extraConfig to avoid misleading file clash with Neovim HM module
        # https://github.com/nix-community/home-manager/issues/1807
        initLua = fileContents ./init.lua;
      };

      xdg.configFile."nvim/lua".source = mkOutOfStoreSymlink nvimLuaSourceHome;
      xdg.configFile."nvim/after".source = mkOutOfStoreSymlink nvimAfterSourceHome;
      xdg.configFile."nvim/lazy-lock.json".source = mkOutOfStoreSymlink nvimLazyLockSourceHome;

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
        pkgs.gcc
        pkgs.basedpyright
        pkgs.stylua
        pkgs.cargo
        pkgs.tree-sitter
      ];
    };
}

