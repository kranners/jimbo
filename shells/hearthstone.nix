{ pkgs ? import <nixpkgs> { } }:

(pkgs.buildFHSUserEnv {
  name = "fhs";
  targetPkgs = pkgs: with pkgs; [ cryptopp webkitgtk python3 python3Packages.virtualenv ];
  # multiPkgs = pkgs: with pkgs; [ cryptopp webkitgtk python3 python3Packages.virtualenv ];
  runScript = "bash";
}).env

