{
  imports = [
    ./git.nix
    ./zsh.nix
    ./scripts.nix
    ./zoxide.nix
    ./alacritty.nix
    ./krabby.nix
    ./espanso.nix
  ];

  programs.direnv = {
    enable = true;
    enableZshIntegration = true;
  };
}
