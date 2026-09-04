{ pkgs, ... }: {
  darwinSystemModule = {
    environment.systemPath = [
      "/opt/homebrew/bin"
      "/opt/homebrew/sbin"
    ];

    homebrew = {
      enable = true;

      casks = [
        "font-iosevka-nerd-font"

        "visual-studio-code"
        "ghostty"
        "mysqlworkbench"
        "browserstacklocal"

        "docker-desktop"
        "microsoft-teams"
        "microsoft-outlook"
        "onedrive"
        "readdle-spark"

        "rectangle"
        "charmstone"
        "raycast"
      ];

      brews = [
        # "docker"
        "direnv"
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
    pkgs.mariadb.client
  ];

  darwinHomeModule.home.packages = [
    pkgs.nurl
    pkgs.nix-output-monitor
    pkgs.mas
    pkgs.svgo
  ];

  nixosSystemModule.environment.systemPackages = [
    pkgs.nixfmt-rfc-style
    pkgs.gnumake
    pkgs.manix
    pkgs.eza
    pkgs.btop
    pkgs.htop
    pkgs.gptfdisk
    pkgs.libnotify
    pkgs.home-manager
    pkgs.busybox
    pkgs.woeusb-ng
    pkgs.ntfs3g
  ];

  nixosHomeModule.home.packages = [
    pkgs.uv
    pkgs.nicotine-plus
    pkgs.jq
    pkgs.nurl

    pkgs.pavucontrol
    pkgs.mpv
    pkgs.blueman
  ];
}
