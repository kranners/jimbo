{ pkgs, config, host, ... }:
let
  inherit (config.home-manager.users.${host.username}.lib.file) mkOutOfStoreSymlink;
  inherit (config.home-manager.users.${host.username}.xdg) configHome;
in
{
  programs.nixvim = {
    extraPlugins = [ pkgs.vimPlugins.obsidian-nvim ];

    extraConfigLua = ''
      -- vim.opt.rtp:append("${configHome}/nvim/notes")

      package.path = package.path .. ';' .. "${configHome}/nvim/notes/?.lua"
      require("notes")
    '';
  };

  home-manager.users.${host.username}.xdg.configFile = {
    "nvim/notes" = {
      recursive = true;
      source = mkOutOfStoreSymlink ./notes;
    };
  };
}
