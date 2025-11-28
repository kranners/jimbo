{
  sharedSystemModule = { pkgs, ... }: {
    fonts.packages = [
      pkgs.nerd-fonts.iosevka
      pkgs.nerd-fonts.jetbrains-mono
    ];
  };
}
