{ pkgs, ... }: {
  homebrew = {
    enable = true;
    casks = [
      "1password"
      "1password-cli"
      "beeper"
      "iterm2"
      "slack"
      "zoom"
      "spotify"
      "google-chrome"
      "firefox"
      "plexamp"
      "microsoft-outlook"
      "aws-vpn-client"
    ];

    brews = [
      "awscli"
      "colima"
      "direnv"
      "fastlane"
      "fnm"
      "gnupg"
      "jq"
      "luajit"
      "openjdk@11"
      "overmind"
      "pyenv-virtualenv"
      "rbenv"
      "redis"
      "watchman"
    ];
  };
}
