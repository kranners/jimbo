{
  nixosSystemModule = {
    boot.kernel.sysctl = {
      "net.ipv4.ip_forward" = 1;
      "net.ipv4.conf.all.forwarding" = 1;
      "net.ipv6.conf.all.forwarding" = 1;
    };

    # https://wiki.archlinux.org/title/Internet_sharing#With_iptables
    networking.nat = {
      enable = true;

      extraCommands = ''
        iptables -t nat -A POSTROUTING -o wlo1 -j MASQUERADE
        iptables -A FORWARD -m conntrack --ctstate RELATED,ESTABLISHED -j ACCEPT
        iptables -A FORWARD -i enp42s0 -o wlo1 -j ACCEPT
      '';
    };
  };
}

