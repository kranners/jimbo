let
  # framer's own wg0 address (modules/hosts/framer/wireguard.nix), reached
  # over WireGuard rather than localhost, since Caddy runs on spike and
  # framer's noVNC bridge does not.
  framerAddress = "10.100.0.5";
in
{
  services.caddy.virtualHosts."vnc.framer.cute.engineer".extraConfig = ''
    reverse_proxy ${framerAddress}:6080
  '';
}
