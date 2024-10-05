{
  programs.chromium = {
    enable = true;

    extensions = [
      { id = "cjpalhdlnbpafiamejdnhcphjbkeiagm"; } # uBlock Origin
      { id = "nngceckbapebfimnlniiiahkandclblb"; } # Bitwarden Password Manager
      { id = "hfjbmagddngcpeloejdejnfgbamkjaeg"; } # Vimium C
      { id = "cdglnehniifkbagbbombnjghhcihifij"; } # Kagi Search
      { id = "hlepfoohegkhhmjieoechaddaejaokhf"; } # Refined Github
      { id = "akahnknmcbmgodngfjcflnaljdbhnlfo"; } # Vertical Tabs in Side Panel
    ];
  };
}
