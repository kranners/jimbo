{ pkgs, config, ... }:
let
  gh-token = "${config.xdg.cacheHome}/.gh-token";
  npm-token = "${config.xdg.cacheHome}/.npm-token";

  export-secrets = pkgs.writeShellApplication {
    name = "export-secrets";

    runtimeInputs = [ pkgs._1password ];

    text = ''
      op read 'op://Employee/GitHub Personal Access Token/token' > ${gh-token}
      op read 'op://Employee/NPM Access Token/credential' > ${npm-token}
    '';
  };
in
{
  home.packages = [ export-secrets ];

  programs.zsh.initExtra = ''
    [[ ! -f ${gh-token} ]] && export-secrets
    [[ ! -f ${npm-token} ]] && export-secrets

    export GITHUB_OAUTH_TOKEN="$(cat ${gh-token})"
    export NPM_TOKEN_INLIGHT="$(cat ${npm-token})"
  '';
}
