{ pkgs, lib, ... }:
let
  extensions = {
    mac-symbols = {
      source = pkgs.fetchFromGitHub {
        owner = "lifesign";
        repo = "espanso-mac-symbols";
        rev = "47f3c87b01de7048a15b8d65f413c62ec36b0090";
        hash = "sha256-n8UXbOn2yyit5IyZ/zAT7F7rbJ63JrX6q/QARFdQI1w=";
      };

      package-version = "0.1.1";
    };

    lorem = {
      source = pkgs.fetchFromGitHub {
        owner = "atika";
        repo = "espanso-lorem";
        rev = "a628127aeb0aa40fc66d1f358654f35684a3809f";
        hash = "sha256-gAkg4Ag7npzXcg2UGzScgmsYvHvmg4YP0aadD+oc9rM=";
      };

      package-version = "0.1.0";
    };

    all-emojis = {
      source = pkgs.fetchFromGitHub {
        owner = "FoxxMD";
        repo = "espanso-all-emojis";
        rev = "f28d9fbaa264f416871a09535cfb3fe64b2cdd16";
        hash = "sha256-0Se/vnps0ERysM8xVLqQaLiqBgA1o1xC6oi9PDbQ7VE=";
      };

      package-version = "0.1.0";
    };

    shruggie = {
      source = pkgs.fetchFromGitHub {
        owner = "spikex";
        repo = "shruggie";
        rev = "fbbba00614fb32b04caf5f003a69c81abf6fab70";
        hash = "sha256-gJZNAQbkKv9u7ZxIQgGb8A7qKSpJpv0db3tKaWUNKlI=";
      };

      package-version = "0.1.0";
    };
  };

  configFiles = lib.mapAttrs'
    (name: package: {
      name = "espanso/match/packages/${name}.yml";
      value = {
        source = "${package.source}/${name}/${package.package-version}/package.yml";
      };
    })
    extensions;

  espanso-pkg = if pkgs.hostPlatform.isLinux then pkgs.espanso-wayland else pkgs.espanso;
in
{
  home.packages = [ espanso-pkg ];
  # xdg.configFile =
  #   {
  #     espanso = {
  #       target = "./espanso/config/default.yml";
  #
  #       text = ''
  #         keyboard_layout: { layout: us }
  #         show_icon: true
  #         show_notifications: false
  #       '';
  #     };
  #   } // configFiles;
}
