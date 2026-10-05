{
  networking.wireguard.interfaces.wg0 = {
    ips = [ "10.100.0.1/24" ];
    listenPort = 51820;
    privateKeyFile = "/var/lib/wireguard/private";
    generatePrivateKeyFile = true;

    peers = [
      {
        name = "piggys-MBP";
        publicKey = "KX06Fz1PeoPnrSAnAqOiYOXVkEOjEjFmRBqsxIP6pDk=";
        allowedIPs = [ "10.100.0.2/32" ];
      }
      {
        name = "github-actions";
        publicKey = "Gbu5Ha59gru26iir0S+qkwBOLNDTz/YQRCA0PPfRglg=";
        allowedIPs = [ "10.100.0.3/32" ];
      }
      {
        name = "phone";
        publicKey = "ZdVqfKi5uQksmXgfy8Q4fC2171Sba3JMMMGkWUCyWDg=";
        allowedIPs = [ "10.100.0.4/32" ];
      }
    ];
  };

  networking.firewall.allowedUDPPorts = [ 51820 ];
}
