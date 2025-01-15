{ pkgs, lib, inputs, ... }:
let
  inherit (pkgs.hostPlatform) isLinux isDarwin;
  inherit (pkgs) fetchFromGitHub;

  alacritty-0-15-0 = pkgs.alacritty.overrideAttrs {
    version = "0.15.0";

    cargoHash = "";

    src = fetchFromGitHub {
      owner = "alacritty";
      repo = "alacritty";
      rev = "5339553";
      hash = "sha256-CAxf0ltvYXYTdjQmLQnRwRRJUBgABbHSB8DxfAbgBdo=";
    };
  };
in
{
  programs.alacritty = {
    enable = true;
    package = alacritty-0-15-0;

    # https://alacritty.org/config-alacritty.html
    settings = {

      # Alacritty config has changed between the versions available on nixpkgs
      # Linux vs nixpkgs Darwin. This will probably come up on an upcoming
      # flake update.
      general = lib.mkIf isLinux {
        import = [
          "${inputs.cyberdream}/extras/alacritty/cyberdream.toml"
        ];
      };

      import = lib.mkIf isDarwin [
        "${inputs.cyberdream}/extras/alacritty/cyberdream.toml"
      ];

      window = {
        padding = { x = 15; y = 15; };
        decorations = "Full";
        opacity = 0.90;
        resize_increments = true;
        option_as_alt = "OnlyLeft";
      };

      colors.transparent_background_colors = true;

      font = {
        size = if isLinux then 12.0 else 16.0;
        normal = { family = "Iosevka Nerd Font Mono"; style = "Regular"; };
        bold = { family = "Iosevka Nerd Font Mono"; style = "Regular"; };
      };
    };
  };

  wayland.windowManager.sway.config = lib.mkIf isLinux {
    terminal = "alacritty";
  };
}
