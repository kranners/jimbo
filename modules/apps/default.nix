{ pkgs, ... }: {
  darwinSystemModule = {
    homebrew = {
      enable = true;

      casks = [
        "font-iosevka-nerd-font"

        "visual-studio-code"
        "ghostty"
        "mysqlworkbench"
        "browserstacklocal"

        "obsidian"
        "busycal"

        "docker-desktop"
        "microsoft-teams"
        "microsoft-outlook"
        "onedrive"
        "discord"
        "readdle-spark"

        "ungoogled-chromium"
        "firefox"
        "vivaldi"

        "plexamp"
        "spotify"

        "rectangle"
        "charmstone"
        "raycast"

        "jagex"
      ];

      brews = [
        "docker"
        "direnv"
        "gnupg"
        "jq"
        "luajit"

        "glab"
      ];

      masApps = {
        # dropover = 1355679052;
        bitwarden = 1352778147;
        kagi = 1622835804;
        ublock-origin-lite = 6745342698;
        "1password" = 1569813296;
        refined-github = 1519867270;
        userscripts = 1463298887;
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
    pkgs.ripgrep
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
    pkgs.spotify
    pkgs.plexamp
    pkgs.nicotine-plus
    pkgs.protonup-qt
    pkgs.r2modman
    pkgs.obsidian
    pkgs.jq
    pkgs.nurl
    pkgs.pokemmo-installer
    pkgs.prismlauncher
    pkgs.bolt-launcher

    pkgs.pavucontrol
    pkgs.mpv
    pkgs.blueberry
    pkgs.wl-clipboard
    pkgs.helvum
    pkgs.vivaldi

    pkgs.lutris
  ];
}
