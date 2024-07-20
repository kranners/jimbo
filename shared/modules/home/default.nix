{
  imports = [
    ./git.nix
    ./zsh.nix
    ./scripts.nix
    ./zoxide.nix
    ./alacritty.nix
  ];

  programs.direnv = {
    enable = true;
    enableZshIntegration = true;
  };
}
