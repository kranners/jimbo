# Aaron's iPhone: the board, the life explorer and Remote Desk on the go

Everything here is reached over WireGuard alone, never the public internet.
The iPhone is one of spike's existing peers, `phone` (`10.100.0.4`) or `phone-2` (`10.100.0.9`), both Aaron's own and both able to reach every other peer through spike.
Each site's name, `kanban`, `life` and `desk` under `spike.cute.engineer`, is a DNS-only Cloudflare record pointing at `10.100.0.1`, so it resolves from any network and its Let's Encrypt certificate, issued by DNS-01, is valid over the tunnel.

## Setting it up

1. In the WireGuard app, edit the phone's tunnel: `Address` its peer's address, `AllowedIPs` `10.100.0.0/24`, `Endpoint` `spike.cute.engineer:51820`, `PersistentKeepalive` `25`.
2. Turn on On-Demand Activation for Cellular and for Wi-Fi, so the tunnel comes up by itself whenever the phone is off the home Wi-Fi and the apps are opened.
   Only `10.100.0.0/24` goes through it, so leaving it on costs nothing else.
3. Open `https://life.spike.cute.engineer`, `https://kanban.spike.cute.engineer` and `https://desk.spike.cute.engineer` in Safari, and for each choose Share, Add to Home Screen.
4. The board and the life explorer ask once for the device gate's password and keep the phone signed in for 30 days; Passwords can save it.
5. Remote Desk asks for its own device login, which `sudo remote-desk add iphone` prints once on spike, and then each machine's screen-sharing password.

The home network answers every DNS query itself and hides private answers, so at home these names may not resolve; an encrypted DNS profile on the phone, such as Cloudflare's 1.1.1.1 app in DNS-only mode, gets the real answer past it.

## Revoking it

- `sudo device-gate-revoke phone-2` (or `phone`) signs that phone out of the board and the life explorer at once, leaving the iPad signed in.
- `sudo remote-desk revoke iphone` ends its Remote Desk logins and screens within 5 seconds.
- Removing its peer from `modules/hosts/spike/wireguard.nix` takes it off WireGuard for good.
- Sign-ins, wrong passwords and lockouts are logged with the peer's name: `journalctl -u device-gate` and `journalctl -u remote-desk`.

## Public HTTPS, not built

The sites could instead be served publicly behind a real login, such as Cloudflare Access with a passkey in front of a Cloudflare Tunnel, as backlogic's API is, so the phone needs no VPN.
That would put Aaron's personal index, the board and his machines' screens one login away from the internet, so it waits for him to ask.
