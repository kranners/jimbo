{ config, ... }:
let
  denoGen = home: "${home}/.cache/deno/gen";
in
{
  # Directory access time is left out of the age, because something reads every
  # directory in /tmp daily, so systemd's own tmp.conf age never passed for one.
  # 00-nixos.conf sorts before tmp.conf, so this line replaces that one.
  # Deno's gen cache gains entries for every new checkout path the runner's lanes make.
  systemd.tmpfiles.rules = [
    "q /tmp 1777 root root abcmBM:1d"
    "e ${denoGen config.users.users.backlogic-runner.home} - - - 2d"
    "e ${denoGen config.users.users.aaron.home} - - - 2d"
  ];
}
