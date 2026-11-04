{
  # The NUC on spike's WireGuard, 10.100.0.14, reaching spike alone, since spike forwards nothing from it.
  # Its private key is /var/lib/secrets/wireguard-private, generated on first boot unless Aaron writes his own there first.
  # spike adds the peer only once nucPublicKey in modules/hosts/spike/wireguard.nix holds the public half, from
  # `sudo wg show wg0 public-key` here, and that is new access, so it waits for Aaron's plain yes.
  networking.wireguard.interfaces.wg0 = {
    ips = [ "10.100.0.14/24" ];
    privateKeyFile = "/var/lib/secrets/wireguard-private";
    generatePrivateKeyFile = true;

    peers = [
      {
        name = "spike";
        publicKey = "PBKY3ThG4AZTjjV1HWjQ293Bp/aLjh3WAw42el9+cQY=";
        endpoint = "spike.cute.engineer:51820";
        allowedIPs = [ "10.100.0.0/24" ];
        persistentKeepalive = 25;
        dynamicEndpointRefreshSeconds = 300;
      }
    ];
  };

  systemd.tmpfiles.rules = [ "d /var/lib/secrets 0700 root root -" ];
}
