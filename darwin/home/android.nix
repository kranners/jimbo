{ lib, ... }: {
  programs.zsh.initContent = lib.mkOrder 550 ''
    export ANDROID_HOME=$HOME/Library/Android/sdk
    export PATH=$PATH:$ANDROID_HOME/emulator
    export PATH=$PATH:$ANDROID_HOME/platform-tools
  '';
}
