{
  nixosSystemModule = { pkgs, ... }: {
    programs.gnupg.agent.enable = true;

    environment.systemPackages = [ pkgs.gnupg ];
  };

  darwinSystemModule.homebrew.brews = [ "gnupg" ];

  sharedHomeModule = { lib, ... }: {
    # Set TTY for GPG to do hardware signing on commits
    programs.zsh.initContent = lib.mkOrder 550 ''
      export GPG_TTY=$(tty)
    '';
  };
}
