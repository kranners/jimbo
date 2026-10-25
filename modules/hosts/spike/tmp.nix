{
  # Directory access time is left out of the age, because something reads every
  # directory in /tmp daily, so systemd's own tmp.conf 10d never passed for one.
  # 00-nixos.conf sorts before tmp.conf, so this line replaces that one.
  systemd.tmpfiles.rules = [ "q /tmp 1777 root root abcmBM:10d" ];
}
