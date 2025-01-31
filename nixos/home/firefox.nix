{ pkgs, inputs, ... }: {
  programs.firefox = {
    enable = true;

    profiles.jimbo = {
      extensions = with inputs.firefox-addons.packages.x86_64-linux; [
        sidebery
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
