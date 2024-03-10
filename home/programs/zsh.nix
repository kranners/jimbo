{pkgs, ...}: {
  programs.zsh = {
    enable = true;

    autosuggestions.enable = true;

    plugins = [
      {
        name = "powerlevel10k";
        src = pkgs.zsh-powerlevel10k;
      }
      {
        name = "fast-syntax-highlighting";
        src = pkgs.zsh-fast-syntax-highlighting;
      }
    ];
  };
}
