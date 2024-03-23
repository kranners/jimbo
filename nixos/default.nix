{
  config,
  pkgs,
  inputs,
  ...
}: {
  imports = [
    ./system/hardware.nix

    # Bootloader
    ./system/boot.nix

    # Basic user info, userspace is configured in home, not nixos
    ./system/users.nix

    # Environment info, system packages, environment variables
    ./system/environment.nix

    # Desktop environment info
    ./system/desktop.nix

    # Overlays and patches
    ./system/overlays.nix

    # Configuration for system programs
    ./packages
  ];

  # Enable Flakes
  nix.package = pkgs.nixFlakes;
  nix.settings.experimental-features = ["nix-command" "flakes"];

  # Allow unfree packages
  nixpkgs.config = {
    allowUnfree = true;

    # Allow for certain insecure packages
    permittedInsecurePackages = [
      "electron-25.9.0"
      "nix-2.16.2"
    ];
  };

  # Enable networking
  networking = {
    networkmanager.enable = true;
    hostName = "jimbo";
  };

  # Set your time zone.
  time.timeZone = "Australia/Melbourne";

  # Select internationalisation properties.
  i18n.defaultLocale = "en_AU.UTF-8";

  i18n.extraLocaleSettings = {
    LC_ADDRESS = "en_AU.UTF-8";
    LC_IDENTIFICATION = "en_AU.UTF-8";
    LC_MEASUREMENT = "en_AU.UTF-8";
    LC_MONETARY = "en_AU.UTF-8";
    LC_NAME = "en_AU.UTF-8";
    LC_NUMERIC = "en_AU.UTF-8";
    LC_PAPER = "en_AU.UTF-8";
    LC_TELEPHONE = "en_AU.UTF-8";
    LC_TIME = "en_AU.UTF-8";
  };

  # XDG Portals
  xdg = {
    autostart.enable = true;
    portal = {
      enable = true;
      extraPortals = [
        pkgs.xdg-desktop-portal
        pkgs.xdg-desktop-portal-gtk
      ];
      config.common.default = "*";
    };
  };

  # Security
  security = {
    pam.services.swaylock = {
      text = ''
        auth include login
      '';
    };
  };

  # Enable CUPS to print documents.
  services.printing.enable = true;

  # Enable sound with pipewire.
  sound.enable = true;
  hardware.pulseaudio.enable = false;
  security.rtkit.enable = true;
  services.pipewire = {
    enable = true;
    alsa.enable = true;
    alsa.support32Bit = true;
    pulse.enable = true;
  };

  # Enable touchpad support (enabled default in most desktopManager).
  # services.xserver.libinput.enable = true;

  # This value determines the NixOS release from which the default
  # settings for stateful data, like file locations and database versions
  # on your system were taken. It‘s perfectly fine and recommended to leave
  # this value at the release version of the first install of this system.
  # Before changing this value read the documentation for this option
  # (e.g. man configuration.nix or on https://nixos.org/nixos/options.html).
  system.stateVersion = "23.11"; # Did you read the comment?
}
