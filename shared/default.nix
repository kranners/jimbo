{ pkgs, ... }: {
  imports = [
    ./nixvim
  ];

  home = {
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

    # See nixvim/plugins/conform.nix
    home.packages = [
      pkgs.eslint_d
      pkgs.prettierd

      pkgs.devenv
      pkgs.nixpkgs-fmt
      pkgs.discord
      pkgs.nurl
      pkgs.nix-output-monitor
    ];
  };
}
