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
    version = "2026.9.2";
    hash = "sha256-bTCH2rMNIVSUgFja6OTH5BQg0qyBaFHnxoyqkyQWyTA=";
  }
  {
    # uBlock Origin Lite, the store no longer serves the Manifest V2 uBlock
    # Origin to Chromium 139 and later.
    id = "ddkjiahejlhfcafbddmgiahcphecmpfh";
    version = "2026.926.2202";
    hash = "sha256-4nreDuH5A7xxCU8DdJM3ix1CoKNM/lFuaT6ha2lBoeY=";
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
    version = "26.9.12";
    hash = "sha256-6nU91pne+T/1bYhL92cn+aJbXlOyF/Pr3s+iWuJ3EXo=";
  }
  {
    # Claude in Chrome
    id = "fcoeoabgfenejglbffodgkkbkcdhcgfn";
    version = "1.0.98";
    hash = "sha256-aNtDr+oRbmHVTwODFzZ12PTMiiTaoW/yhxmRypaEPXg=";
  }
]
