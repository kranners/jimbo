{ pkgs, ... }: {
  services.udev.packages = [ pkgs.via pkgs.vial ];
  environment.systemPackages = [ pkgs.vial ];
}
