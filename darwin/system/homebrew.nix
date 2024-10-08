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

    masApps = {
      "flow" = 1423210932; # https://www.flow.app/
      "just-focus-2" = 1142151959; # https://getjustfocus.com/
      "dropover" = 1355679052; # https://dropoverapp.com/
    };
  };
}
