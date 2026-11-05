# render.py with its browsers and pinned libraries filled in, and the folders it writes and reads, so spike's command and the flake check `butler-render` run the same script.
{ pkgs, lib }:
paths:
let
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

  substitutions = {
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
    "@browsers@" = browsers;
    "@moods@" = "${../../../../assets/butler/moods}";
  }
  // lib.mapAttrs' (name: value: lib.nameValuePair "@${name}@" value) paths;
in
builtins.replaceStrings (lib.attrNames substitutions) (map toString (
  lib.attrValues substitutions
)) (builtins.readFile ./render.py)
