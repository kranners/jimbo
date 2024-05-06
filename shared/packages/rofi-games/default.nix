{ lib
, stdenv
, fetchFromGitHub
, rustPlatform
, cargo
, just
, rofi-wayland
, pkg-config
, glib
, cairo
, pango
,
}:
stdenv.mkDerivation (finalAttrs: {
  pname = "rofi-games";
  version = "1.6.8";

  src = fetchFromGitHub {
    owner = "Rolv-Apneseth";
    repo = "rofi-games";
    rev = "v${finalAttrs.version}";
    hash = "sha256-YsrckS89riQgW4xGcSwQUeRQileOldMTXPICsaLOfbk=";
  };

  cargoDeps = rustPlatform.fetchCargoTarball {
    name = "${finalAttrs.pname}-${finalAttrs.version}";
    inherit (finalAttrs) src;
    hash = "sha256-QSugPmlTrj61T4VmCWThf4X8uFM08VMXsdDDrh7nNBU=";
  };

  patches = [
    # fix the install locations of files and set default just task
    ./fix-justfile.patch
  ];

  env.PKGDIR = placeholder "out";

  nativeBuildInputs = [ rustPlatform.cargoSetupHook cargo just rofi-wayland pkg-config ];

  buildInputs = [ glib cairo pango ];

  meta = {
    description = "A rofi plugin which adds a mode that will list available games for launch along with their box art";
    homepage = "https://github.com/Rolv-Apneseth/rofi-games";
    license = lib.licenses.gpl2Only;
    maintainers = with lib.maintainers; [ tomasajt ];
  };
})
