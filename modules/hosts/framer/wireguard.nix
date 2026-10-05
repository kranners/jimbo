{
  networking.wireguard.interfaces.wg0 = {
    ips = [ "10.100.0.4/24" ];
    privateKeyFile = "/var/lib/wireguard/private";
    generatePrivateKeyFile = true;

    peers = [
      {
        name = "spike";
        publicKey = "PBKY3ThG4AZTjjV1HWjQ293Bp/aLjh3WAw42el9+cQY=";
        endpoint = "spike.cute.engineer:51820";
        allowedIPs = [ "10.100.0.0/24" ];
        persistentKeepalive = 25;
      }
    ];
  };
}
