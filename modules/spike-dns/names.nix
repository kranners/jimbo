# Every name spike's Caddy serves over WireGuard alone, each resolving to spike's 10.100.0.1.
# spike's resolver on wg0 answers them (modules/hosts/spike/dns.nix), which asserts that every Caddy site under
# cute.engineer is listed here, and each Mac sends only these names to it (./default.nix).
# spike.cute.engineer itself is left out, since it is spike's public WireGuard endpoint and must resolve without the tunnel.
[
  "backlogic.spike.cute.engineer"
  "browser.spike.cute.engineer"
  "desk.spike.cute.engineer"
  "grafana.spike.cute.engineer"
  "kanban.spike.cute.engineer"
  "life.spike.cute.engineer"
  "money.spike.cute.engineer"
  "app.bowerbird.cute.engineer"
  "vnc.framer.cute.engineer"
]
