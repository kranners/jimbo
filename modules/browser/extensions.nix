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
    version = "2026.10.0";
    hash = "sha256-8v63/EbSVQvvm2mvHMNYrqJrkKlHZF+d4W7BTZKW72k=";
  }
  {
    # uBlock Origin Lite, the store no longer serves the Manifest V2 uBlock
    # Origin to Chromium 139 and later.
    id = "ddkjiahejlhfcafbddmgiahcphecmpfh";
    version = "2026.1018.2229";
    hash = "sha256-VZ0Q733LlrxOgS3ms/8MLmx6vKV4Mk2Nev19jPeKbdc=";
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
    version = "26.10.20";
    hash = "sha256-uij61TGNjBAqIVkKQjYNpfrK07EH8oNJxBA/WHVcMRE=";
  }
  {
    # Claude in Chrome
    id = "fcoeoabgfenejglbffodgkkbkcdhcgfn";
    version = "1.0.101";
    hash = "sha256-yQO71kndmQf1WIjJBGk9ixE928oOL7M7OcdcQYV/7is=";
  }
]
