{ ... }: {
  services.nix-daemon.enable = true;
  nix.settings.experimental-features = "nix-command flakes";

  users.users.aaronpierce = {
    name = "aaronpierce";
    home = "/Users/aaronpierce";
  };

  programs.zsh.enable = true;

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
