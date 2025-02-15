{ pkgs, ... }: {
  darwinSystemModule = {
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
        "codeship/taps/jet"
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
        "just-focus-2" = 1142151959; # https://getjustfocus.com/
        "dropover" = 1355679052; # https://dropoverapp.com/
      };
    };
  };

  sharedHomeModule.home.packages = [
    pkgs.bat
    pkgs.eslint_d
    pkgs.prettierd
    pkgs.rubocop
    pkgs.cachix

    pkgs.devenv
    pkgs.just
  ];

  darwinHomeModule.home.packages = [
    pkgs.nixpkgs-fmt
    pkgs.nurl
    pkgs.nix-output-monitor
    pkgs.mas
    pkgs.nodePackages.svgo
    pkgs.fnm
  ];

  nixosSystemModule.environment.systemPackages = [
    pkgs.nixfmt-rfc-style
    pkgs.gnumake
    pkgs.gnupg
    pkgs.manix
    pkgs.eza
    pkgs.btop
    pkgs.htop
    pkgs.gptfdisk
    pkgs.libnotify
    pkgs.pipewire
    pkgs.home-manager
    pkgs.busybox
  ];

  nixosHomeModule.home.packages = [
    pkgs.spotify
    pkgs.plexamp
    pkgs.nicotine-plus
    pkgs.protonup-qt
    pkgs.r2modman
    pkgs.obsidian
    pkgs.ripgrep
    pkgs.jq
    pkgs.nh
    pkgs.nurl

    pkgs.pavucontrol # Audio control
    pkgs.nemo-with-extensions # File manager
    pkgs.mpv # Media playback
    pkgs.blueberry # Bluetooth manager
    pkgs.wl-clipboard # Clipboard manager
    pkgs.helvum # Multi-audio output
  ];
}
