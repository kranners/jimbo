{
  config,
  pkgs,
  lib,
  ...
}:
let
  python = pkgs.python3Packages;

  browsers = pkgs.playwright-driver.browsers.override {
    withChromium = false;
    withFirefox = false;
    withWebkit = false;
    withFfmpeg = false;
  };

  bundle =
    name: version: path: hash:
    pkgs.fetchurl {
      url = "https://cdn.jsdelivr.net/npm/${name}@${version}/${path}";
      inherit hash;
    };

  libraries = {
    "@vega@" =
      bundle "vega" "6.4.0" "build/vega.min.js"
        "sha256-j2o1h8+NT0LH4IEg4+sF0GfnRtVU450tz1KswL1boo8=";
    "@vegaLite@" =
      bundle "vega-lite" "6.5.0" "build/vega-lite.min.js"
        "sha256-g+IV6E4wjuhoj6ZQO6Dxz4o8BcDWHfKEGguSv4aAngA=";
    "@vegaEmbed@" =
      bundle "vega-embed" "7.3.0" "build/vega-embed.min.js"
        "sha256-sUVcq6L7GnL7RgJboLoTFuLbx/DdQKP2BAFyv5wIupE=";
    "@mermaid@" =
      bundle "mermaid" "12.2.0" "dist/mermaid.min.js"
        "sha256-qKam+AWwdKgmGiglyG+ZyAVKyzs19Qu34kpPnyw8O58=";
  };

  substitutions = libraries // {
    "@browsers@" = browsers;
    "@outbox@" = "${config.users.users.butler.home}/outbox";
  };

  render =
    pkgs.writers.writePython3Bin "render"
      {
        libraries = [ python.playwright ];
        flakeIgnore = [
          "E402"
          "E501"
        ];
      }
      (
        builtins.replaceStrings (lib.attrNames substitutions) (map toString (
          lib.attrValues substitutions
        )) (builtins.readFile ./butler-render/render.py)
      );

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
      render html [width] | render svg [width] | render mermaid [width] | render vega-lite [width] (the source on stdin; width in CSS pixels, 1000 unless given)
    '';
    stdin = true;
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
