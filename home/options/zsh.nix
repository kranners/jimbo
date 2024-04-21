{ pkgs, ... }: {
  programs.zsh = {
    enable = true;

    plugins = [
      {
        name = "powerlevel10k";
        src = pkgs.zsh-powerlevel10k;
        file = "share/zsh-powerlevel10k/powerlevel10k.zsh-theme";
      }
      {
        name = "fast-syntax-highlighting";
        src = pkgs.zsh-fast-syntax-highlighting;
      }
      {
        name = "powerlevel10k-lean-config";
        src = pkgs.zsh-powerlevel10k;
        file = "share/zsh-powerlevel10k/config/p10k-lean.zsh";
      }
    ];
  };
}
