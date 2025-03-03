{ pkgs, config, host, ... }:
let
  inherit (config.home-manager.users.${host.username}.lib.file) mkOutOfStoreSymlink;
  inherit (config.home-manager.users.${host.username}.xdg) configHome;
  inherit (config.home-manager.users.${host.username}.home) homeDirectory;
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
    nvim.source = mkOutOfStoreSymlink "${homeDirectory}/workspace/jimbo/modules/nixvim/plugins/notes";
  };
}
