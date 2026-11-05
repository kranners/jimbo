{
  config,
  pkgs,
  lib,
  ...
}:
let
  python = pkgs.python3Packages;

  # What it draws for butler is saved in the asset store too, but for the cards spike draws with it, which set BUTLER_ASSETS_AUTO=0.
  # The only files a page may load, by reference, are the asset store, the outbox, the mood pictures and the scene pictures, the same folders attach_file reads.
  source = import ./butler-render/source.nix { inherit pkgs lib; } {
    outbox = "${config.users.users.butler.home}/outbox";
    asset = lib.getExe config.butler.assets.package;
    store = "${config.users.users.butler.home}/assets";
    scenes = config.butler.scenes.dir;
    sceneGroups = lib.concatStringsSep ":" (lib.attrNames config.butler.scenes.catalog);
  };

  render = pkgs.writers.writePython3Bin "render" {
    libraries = [ python.playwright ];
    flakeIgnore = [
      "E402"
      "E501"
    ];
  } source;

  both = [
    "interactive"
    "cron"
  ];
in
{
  assertions = [
    {
      assertion = python.playwright.driver.version == pkgs.playwright-driver.version;
      message = "butler's render needs python3Packages.playwright's driver, ${python.playwright.driver.version}, to match the playwright-driver its browsers come from, ${pkgs.playwright-driver.version}";
    }
  ];

  butler.commands.render = {
    package = render;
    description = ''
      Render HTML, SVG, a Mermaid diagram or a Vega-Lite chart to a PNG in the outbox, and print its path to attach.
      render html [width] | render svg [width] | render mermaid [width] | render vega-lite [width] (the source on stdin, up to 512 KB; width in CSS pixels, 1000 unless given)
      Butler's own pictures load by reference in img src, srcset, CSS url() and SVG href: asset://<name> from the asset store, outbox://<file>, mood://<name> for the mood pictures and scene://<group>/<name>; nothing else loads, no file://, no other path and no network, so inline anything else as a data: URI.
    '';
    stdin = true;
    stdinBytes = 512 * 1024;
    rules = [
      {
        match = [ "*" ];
        lanes = both;
      }
      {
        match = [
          "*"
          "*"
        ];
        lanes = both;
      }
    ];
    skill = ./butler-skills/render;
  };
}
