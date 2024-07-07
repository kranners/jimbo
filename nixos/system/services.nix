{ pkgs, ... }: {
  services = {
    # smb and such for nemo
    gvfs.enable = true;

    # enable mounting drives in nemo
    udisks2.enable = true;
  };

  environment.systemPackages = [ pkgs.file-roller ];
}
