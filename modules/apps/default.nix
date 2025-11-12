{ pkgs, ... }: {
  darwinSystemModule = {
    homebrew = {
      enable = true;

      casks = [
        "font-iosevka-nerd-font"

          "visual-studio-code"
          "ghostty"
          "obsidian"
          "busycal"

          "slack"
          "discord"
          "readdle-spark"

          "plexamp"
          "spotify"

          "rectangle"
          "charmstone"
          "raycast"

          "jagex"
      ];

      brews = [
        "direnv"
          "gnupg"
          "jq"
          "luajit"
      ];

      masApps = {
        "dropover" = 1355679052;
        "bitwarden" = 1352778147;
      };
    };
  };

  sharedHomeModule.home.packages = [
    pkgs.bat
      pkgs.prettierd
      pkgs.rubocop
      pkgs.cachix
      pkgs.docker-compose
      pkgs.fnm

      pkgs.devenv
      pkgs.just
      pkgs.act
      pkgs.nh
  ];

  darwinHomeModule.home.packages = [
    pkgs.nurl
      pkgs.nix-output-monitor
      pkgs.mas
      pkgs.nodePackages.svgo
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
      pkgs.woeusb-ng
      pkgs.ntfs3g
  ];

  nixosHomeModule.home.packages = [
    pkgs.uv
      pkgs.code-cursor
      pkgs.spotify
      pkgs.plexamp
      pkgs.nicotine-plus
      pkgs.protonup-qt
      pkgs.r2modman
      pkgs.obsidian
      pkgs.ripgrep
      pkgs.jq
      pkgs.nurl
      pkgs.pokemmo-installer
      pkgs.prismlauncher

      pkgs.pavucontrol # Audio control
      pkgs.mpv # Media playback
      pkgs.blueberry # Bluetooth manager
      pkgs.wl-clipboard # Clipboard manager
      pkgs.helvum # Multi-audio output
  ];
               }
