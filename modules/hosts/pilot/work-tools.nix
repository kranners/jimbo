# Tooling the work repositories expect on this Mac.
{
  darwinSystemModule.homebrew = {
    # The repositories pin uv 0.13, newer than nixpkgs carries.
    brews = [ "uv" ];

    # The work repositories' browser tests launch the Chrome channel.
    casks = [ "google-chrome" ];
  };

  darwinHomeModule =
    { pkgs, ... }:
    {
      home.packages = [
        pkgs.terraform
        pkgs.tflint
        pkgs.lefthook
        pkgs.awscli2
        pkgs.aws-sam-cli

        # OpenSSL 3 ahead of macOS's LibreSSL, which rejects `openssl req -noenc`.
        pkgs.openssl
      ];
    };
}
