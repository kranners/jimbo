{ pkgs, config, host, ... }:
let
  inherit (config.home-manager.users.${host.username}.lib.file) mkOutOfStoreSymlink;
  inherit (config.home-manager.users.${host.username}.xdg) configHome;
in
{
  programs.nixvim = {
    extraPlugins = [ pkgs.vimPlugins.obsidian-nvim ];

    extraConfigLua = ''
      package.path = package.path .. ';' .. "${configHome}/nvim/?.lua"
      require("notes")
    '';
  };

  home-manager.users.${host.username}.xdg.configFile = {
    nvim = {
      recursive = true;
      source = mkOutOfStoreSymlink ./notes;
    };
  };
}
