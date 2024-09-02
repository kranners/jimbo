{
  programs.zsh.enable = true;

  home = {
    programs.zsh.initExtraBeforeCompInit = ''
      export ANDROID_HOME=$HOME/Library/Android/sdk
      export PATH=$PATH:$ANDROID_HOME/emulator
      export PATH=$PATH:$ANDROID_HOME/platform-tools
    '';
  };
}
