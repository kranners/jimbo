# Remote Desk: Aaron's machines from his iPad

Remote Desk is a web remote desktop on spike, at `https://desk.spike.cute.engineer`, for driving piggys-MBP, pilot and the jimbo PC from the iPad the way butler does.
It is `modules/hosts/spike/remote-desk.nix`, a small Python gateway (`remote-desk/server.py`) serving a launcher and a touch-first noVNC viewer (`remote-desk/web`), installable as a PWA.

## How it works

- Caddy serves it over WireGuard alone, to the peers in `remoteDesk.viewers`: `ipad`, once `modules/hosts/spike/wireguard.nix` has a peer of that name, `piggys-MBP`, `phone` and `phone-2`.
- Caddy also aborts any request whose `Origin` is not the site itself, and the gateway checks it again.
- Each device logs in with its own name and a random password that `sudo remote-desk add <device>` prints once, stored on spike only as a scrypt hash in `/var/lib/remote-desk/devices.json`.
- A login lasts until 15 minutes without a touch or key, or 12 hours, and works only from the WireGuard address it logged in from.
- Five wrong passwords from one address lock it out for 15 minutes, and twenty from anywhere in an hour lock every login for an hour.
- The launcher shows each machine as up, locked, at its login window, refused or down, the same probes as butler's `mac hosts`: ssh's port first, then the key's status command.
  It also shows when butler holds an ssh connection to that machine and which other devices are viewing it.
- Connecting opens a fresh ssh connection from spike with the gateway's own key, `/var/lib/remote-desk/ssh/id_ed25519`, generated on spike on the service's first start, separate from butler's key and its `mac` sessions.
  On the Macs and Windows it forwards to the machine's own VNC on `127.0.0.1:5900`; on jimbo's NixOS its forced command pipes wayvnc's socket over the session, since OpenSSH refuses unix-socket forwards to a key with `permitopen`.
- The machine then asks for its own screen-sharing password, which the gateway never stores; the iPad's Passwords app can fill it in.
  wayvnc on jimbo's NixOS has no password, so there the gateway login and Hyprland's own lock screen are the gates.
- Every login, failed login, lockout, screen opened and closed is logged in spike's journal, `journalctl -u remote-desk`, never a password.

On each machine the gateway's key is accepted only from spike's `10.100.0.1`, under `restrict`, and its forced command only prints whether the screen is locked, or on jimbo's NixOS also carries VNC, so it runs nothing else.
On the Macs and Windows it may forward to `127.0.0.1:5900` alone.
No machine opens a new port, and Screen Sharing stays blocked by pf on every Mac interface but loopback.
Its public half goes in `modules/butler-access/remote-desk.nix`, and until then no machine accepts it.

## Threat model

- Someone on the internet cannot reach it: Caddy listens on WireGuard alone and aborts anyone but Aaron's own peers.
- A stolen iPad, locked, gives nothing: the PWA's login cookie is useless after 15 idle minutes, and revoking the device on spike ends its sessions and screens within 5 seconds.
- A stolen iPad, unlocked within 15 minutes of use, gives the screens it was logged in to, each still behind its own lock screen, until Aaron revokes it or removes its WireGuard peer.
- Someone who learns the device password still needs the iPad's WireGuard key, and the other way round.
- A copied login cookie works only from the WireGuard address that logged in.
- A compromise of the gateway itself reaches each Mac's and the PC's screen-sharing port, behind its VNC password, and their lock state, but no shell, since the key runs only its forced command.
- Butler and the iPad can drive the same screen at once; the launcher and the viewer's title say when butler is connected, but nothing stops either.
- pilot is the employer's managed Mac: the gateway changes nothing there but adding its restricted key, keep-awake stays off by default, and its screen locks as its policy says.

What it cannot do: unlock a locked screen except by typing its password on its lock screen, pass FileVault's screen after a restart, or wake a machine that is asleep or off, since none of them has Wake-on-LAN over Wi-Fi.

## Turning it off

- At once: `sudo remote-desk revoke --all` ends every login, and `sudo systemctl stop remote-desk` stops the gateway until the next switch.
- For good: `remoteDesk.enable = false` in `modules/hosts/spike/default.nix`, and `publicKey = null` in `modules/butler-access/remote-desk.nix` to withdraw the key from the Macs and jimbo's NixOS.
- On Windows: `windows-remote-desk.ps1 -Remove` in an administrator PowerShell.
- A single machine: drop it from `remoteDesk.hosts`.

## Starting it

On spike, once this lands:

1. `sudo remote-desk key` prints the gateway's public key; put it in `modules/butler-access/remote-desk.nix` and land that, then switch both Macs (`just`).
2. On the PC's Windows, in an administrator PowerShell: `powershell -ExecutionPolicy Bypass -File docs\windows-remote-desk.ps1 -PublicKey '<that key>'`.
3. `sudo remote-desk add ipad` and keep the password it prints.
4. Make a DNS-only A record `desk.spike.cute.engineer` pointing at `10.100.0.1` in Cloudflare, like the other `*.spike.cute.engineer` names.

On the iPad:

1. Join WireGuard as the peer `ipad`, which the sibling iPad self-fix adds to spike.
2. Open `https://desk.spike.cute.engineer` in Safari, Share, Add to Home Screen, and open Remote Desk from the Home Screen.
3. Log in as `ipad` with the password, and let Passwords save it.
4. Tap a machine, then give its screen-sharing password: a Mac's is in `~/.local/state/butler-access/vnc-password` on it, the PC's in `C:\ProgramData\butler-access\vnc-password`.

## Using it

- Tap clicks, two-finger tap right-clicks, two-finger drag scrolls, and drag drags, noVNC's own touch gestures.
- ⌘ (Win on Windows and Linux), Ctrl, ⌥ (Alt) and ⇧ hold for the next key; a double tap locks one until tapped again.
- ⌨ brings up the iPad's keyboard; a Magic Keyboard's ⌘ and Ctrl shortcuts reach the remote machine too, unless iPadOS takes them first.
- ✋ switches to pan mode, where one finger moves around and two pinch to zoom, so jimbo's 5120x1440 screen can be read; Fit shows the whole screen and 1:1 shows real pixels.
- ⋯ has Ctrl Alt Del, Delete, Home, End, Page up and down, typing a pasted text, and hiding the toolbar.

## Native app fallback, not built

A native VNC app such as Screens or Jump Desktop can tunnel through spike with its own iPad key, but that needs a jump account on spike and a new key on every machine, which this change does not add.
To build it later: a system user on spike whose `authorized_keys` line for the iPad key is `restrict,port-forwarding,permitopen="10.100.0.2:22",permitopen="10.100.0.11:22",permitopen="10.100.0.8:22"`, and on each machine the same key under the gateway's restrictions, then in the app an SSH tunnel to `spike` as that user, onward to the machine, forwarding to `127.0.0.1:5900`.
A shell from the iPad is the remote machine's own terminal through Remote Desk; a real ssh shell would need that key given full shell access on each machine, which is a wider grant than Remote Desk's.
