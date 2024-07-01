{ config
, pkgs
, lib
, inputs
, ...
}:
let
  betterfox = pkgs.fetchFromGitHub {
    owner = "yokoffing";
    repo = "Betterfox";
    rev = "9756922ee951f9c0dd09f1e7037b93089a661963";
    hash = "sha256-i6fxW6hOOUWjWJ7lhX5qjEh9tyE2JyD6vwPEsfov7fY=";
  };
in
{
  programs.firefox = {
    enable = true;

    profiles.jimbo = {
      extensions = with inputs.firefox-addons.packages.x86_64-linux; [
        tree-style-tab
        kagi-search
        ublock-origin
        vimium
        bitwarden
      ];

      settings = {
        "signon.rememberSignons" = false;
        "identity.fxaccounts.enabled" = false;
        "extensions.autoDisableScopes" = false;
        "toolkit.legacyUserProfileCustomizations.stylesheets" = true;
      };

      userChrome = ''
        #TabsToolbar { visibility: collapse !important }
      '';

      search = {
        force = true;
        default = "Kagi";

        engines =
          let
            query-param = {
              name = "query";
              value = "{searchTerms}";
            };

            nix-search-params = [
              {
                name = "type";
                value = "packages";
              }
              {
                name = "channel";
                value = "unstable";
              }
              query-param
            ];
          in
          {
            "Kagi" = {
              urls = [
                {
                  template = "https://kagi.com/search";
                  params = [
                    {
                      name = "q";
                      value = "{searchTerms}";
                    }
                  ];
                }
              ];
            };

            "Nix Packages" = {
              urls = [
                {
                  template = "https://search.nixos.org/packages";
                  params = nix-search-params;
                }
              ];

              icon = "${pkgs.nixos-icons}/share/icons/hicolor/scalable/apps/nix-snowflake.svg";
              definedAliases = [ "np" ];
            };

            "Nix Options" = {
              urls = [
                {
                  template = "https://search.nixos.org/options";
                  params = nix-search-params;
                }
              ];

              icon = "${pkgs.nixos-icons}/share/icons/hicolor/scalable/apps/nix-snowflake.svg";
              definedAliases = [ "no" ];
            };

            "Home Manager Options" = {
              urls = [
                {
                  template = "https://home-manager-options.extranix.com";
                  params = [
                    {
                      name = "release";
                      value = "master";
                    }
                    query-param
                  ];
                }
              ];

              icon = "${pkgs.nixos-icons}/share/icons/hicolor/scalable/apps/nix-snowflake.svg";
              definedAliases = [ "nh" ];
            };
          };
      };
    };
  };
}
