{
  networking.wireguard.interfaces.wg0 = {
    ips = [ "10.100.0.1/24" ];
    listenPort = 51820;
    privateKeyFile = "/var/lib/wireguard/private";
    generatePrivateKeyFile = true;

    peers = [
      {
        name = "piggys-MBP";
        publicKey = "1nyyas9dwolxY1nGyU9hGTtZ8SnOvKLW35ZOgu6+Y1U=";
        allowedIPs = [ "10.100.0.2/32" ];
      }
      {
        name = "github-actions";
        publicKey = "Gbu5Ha59gru26iir0S+qkwBOLNDTz/YQRCA0PPfRglg=";
        allowedIPs = [ "10.100.0.3/32" ];
      }
    ];
  };

  networking.firewall.allowedUDPPorts = [ 51820 ];
}
