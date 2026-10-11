{
  services.caddy.virtualHosts."vnc.framer.cute.engineer".extraConfig = ''
    reverse_proxy 10.100.0.5:6080
  '';
}
