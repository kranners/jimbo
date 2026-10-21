{ config, lib, ... }:
let
  forwardingPeers = [
    "piggys-MBP"
    "phone"
    "phone-2"
    "framer"
    "tower"
  ];
  forwardingAddresses = lib.concatMap (peer: peer.allowedIPs) (
    lib.filter (
      peer: lib.elem peer.name forwardingPeers
    ) config.networking.wireguard.interfaces.wg0.peers
  );
in
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
      {
        name = "framer";
        publicKey = "5wlH0AO617/X46akfNolE0HZjOf+NYHcJOKffYfVhww=";
        allowedIPs = [ "10.100.0.5/32" ];
      }
      {
        name = "rylee";
        publicKey = "tvFk4wzKSPm6IbX/0ydl1crn56BD4TNu14DKmZDqDG0=";
        allowedIPs = [ "10.100.0.6/32" ];
      }
      {
        name = "tower";
        publicKey = "IA5R1V9DCdOVwyi6oY+RFturexAtizQnXU2MgzsKdi0=";
        allowedIPs = [ "10.100.0.7/32" ];
      }
      {
        name = "windows";
        publicKey = "Z7V1ro+dr7/wPsnfyDq8rBPqeJ0M+NuI7t1O1uYvFxE=";
        allowedIPs = [ "10.100.0.8/32" ];
      }
      {
        name = "phone-2";
        publicKey = "+kOfkc7PFX6OFf9mq1ShAZ4/fT+1yC3d4IXebrQvaCI=";
        allowedIPs = [ "10.100.0.9/32" ];
      }
      {
        name = "rylee-2";
        publicKey = "sXVMpbkWoPiFD1Czg4clq/bb0ycA32ODGdDnHDLFn1E=";
        allowedIPs = [ "10.100.0.10/32" ];
      }
    ];
  };

  networking.firewall.allowedUDPPorts = [ 51820 ];

  # Rylee's backlogic instance on tower, served only to private addresses.
  networking.hosts."10.100.0.7" = [ "ideas.noodlebra.in" ];

  boot.kernel.sysctl."net.ipv4.ip_forward" = 1;

  networking.firewall.extraCommands = ''
    iptables -D FORWARD -i wg0 -j spike-wg0-forward 2> /dev/null || true
    iptables -F spike-wg0-forward 2> /dev/null || true
    iptables -X spike-wg0-forward 2> /dev/null || true
    iptables -N spike-wg0-forward
    iptables -A spike-wg0-forward -m conntrack --ctstate ESTABLISHED,RELATED -j ACCEPT
    ${lib.concatMapStrings (address: ''
      iptables -A spike-wg0-forward -s ${address} -o wg0 -j ACCEPT
    '') forwardingAddresses}
    iptables -A spike-wg0-forward -j DROP
    iptables -I FORWARD -i wg0 -j spike-wg0-forward
  '';

  networking.firewall.extraStopCommands = ''
    iptables -D FORWARD -i wg0 -j spike-wg0-forward 2> /dev/null || true
  '';
}
