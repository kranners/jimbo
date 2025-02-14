{ pkgs, ... }:
let
  excludes-file-path = "personal.gitignore";

  load-personal-shell = pkgs.writeShellApplication {
    name = "s";

    text = ''
      nix-shell shell.personal.nix --command zsh
    '';
  };
in
{
  home = {
    packages = [ load-personal-shell ];

    file.${excludes-file-path}.text = ''
      shell.personal.nix
    '';
  };

  programs.git.extraConfig.core.excludesfile = "~/${excludes-file-path}";
}
