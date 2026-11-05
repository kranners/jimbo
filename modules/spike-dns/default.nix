# Split DNS for spike's WireGuard-only names on the Macs: one /etc/resolver file per name sends only that name, and
# its subdomains, to spike's resolver on 10.100.0.1, which the tunnel reaches, so every other lookup keeps the
# network's own DNS and a dead spike or a tunnel that is off breaks nothing but these names.
let
  names = import ./names.nix;
in
{
  darwinSystemModule.environment.etc = builtins.listToAttrs (
    map (name: {
      name = "resolver/${name}";
      value.text = ''
        nameserver 10.100.0.1
        timeout 2
      '';
    }) names
  );
}
