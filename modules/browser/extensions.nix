{ pkgs, ... }:

let
  # The Chrome Web Store only serves the newest release of an extension, so
  # every bump to a hash here is also a version bump.
  fetchExtension =
    {
      id,
      version,
      hash,
    }:
    {
      inherit id version;
      crxPath = pkgs.fetchurl {
        name = "${id}-${version}.crx";
        url =
          "https://clients2.google.com/service/update2/crx"
          + "?response=redirect&acceptformat=crx3&prodversion=140&x=id%3D${id}%26uc";
        inherit hash;
      };
    };
in
map fetchExtension [
  {
    # Bitwarden
    id = "nngceckbapebfimnlniiiahkandclblb";
    version = "2026.10.1";
    hash = "sha256-2SlT6sQNZPWzjiVNIZa6uwvwxegcHZr6rkzYilW6tCw=";
  }
  {
    # uBlock Origin Lite, the store no longer serves the Manifest V2 uBlock
    # Origin to Chromium 139 and later.
    id = "ddkjiahejlhfcafbddmgiahcphecmpfh";
    version = "2026.1026.1812";
    hash = "sha256-Z2P/MMt7ib87QRkIwDZ0tdTpjBKjj7rndv0FfRqNGDc=";
  }
  {
    # Vimium C
    id = "hfjbmagddngcpeloejdejnfgbamkjaeg";
    version = "2.12.2";
    hash = "sha256-1kiLH+QIjOIheJXFNE/BKJ7tWZLvwHpr6ec1cLIlBCM=";
  }
  {
    # Refined GitHub
    id = "hlepfoohegkhhmjieoechaddaejaokhf";
    version = "26.10.26";
    hash = "sha256-Zc1hPio5K0R+SL3dtq9ZrTTxstchX86vswkpbpGCM8Q=";
  }
  {
    # Claude in Chrome
    id = "fcoeoabgfenejglbffodgkkbkcdhcgfn";
    version = "1.0.104";
    hash = "sha256-yg//bd67w3gl2cE1c18MetXAJJYDj69mkh15uy5Ltpo=";
  }
  {
    # Tampermonkey
    id = "dhdgffkkebhmkfjojejmpbldmpobfkfo";
    version = "5.5.1";
    hash = "sha256-tRZ5N4F+Y2reukYu2b+bMv8BwoiPeKmvxqpPjmVf6HI=";
  }
  {
    # React Developer Tools
    id = "fmkadmapgofadopljbjfkapdkoienihi";
    version = "8.0.0";
    hash = "sha256-2S4RIqFjYsxVEJJwaKWxqNULQ+HzviXDEX98AFgHswI=";
  }
  {
    # Proton VPN
    id = "jplgfhpmjnbigmhklmmbgecoobifkmpa";
    version = "1.3.6";
    hash = "sha256-vTwPXkBKlOA0FUzaQTD1hldFzMevtSf41IHl2zkmQa0=";
  }
]
