{ ... }: {
  homebrew = {
    enable = true;
    casks = [
      "1password"
      "1password-cli"
      "beeper"
      "iterm2"
      "slack"
      "zoom"
      "displaylink"
      "postman"
      "spotify"
      "google-chrome"
      "firefox"
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
