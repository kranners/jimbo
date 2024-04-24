{
  config,
  pkgs,
  lib,
  inputs,
  ...
}: let
  makeNixvim = inputs.nixvim.legacyPackages.${pkgs.system}.makeNixvim;
  
  nixvim = {};
in {
  home.packages = [ ( makeNixvim nixvim ) ];
}