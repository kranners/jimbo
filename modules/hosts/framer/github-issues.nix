{ pkgs, ... }:
let
  tokenFile = "/var/lib/secrets/github-issues-token";

  github-issue = pkgs.writeShellApplication {
    name = "github-issue";

    runtimeInputs = [
      pkgs.curl
      pkgs.jq
    ];

    text = ''
      usage() {
        echo "usage: github-issue repos" >&2
        echo "       github-issue create <owner/repo> <title> <body>" >&2
        exit 2
      }

      github() {
        curl --silent --show-error --fail-with-body \
          --header "Authorization: Bearer $(cat ${tokenFile})" \
          --header "Accept: application/vnd.github+json" \
          --header "X-GitHub-Api-Version: 2022-11-28" \
          "$@"
      }

      [ $# -ge 1 ] || usage

      case "$1" in
        repos)
          github "https://api.github.com/user/repos?affiliation=owner&per_page=100" \
            | jq -r '.[] | select(.archived | not) | select(.has_issues) | "\(.full_name)\t\(.description // "")"'
          ;;
        create)
          [ $# -eq 4 ] || usage
          jq --null-input --arg title "$3" --arg body "$4" '{title: $title, body: $body}' \
            | github --data @- "https://api.github.com/repos/$2/issues" \
            | jq -r '"#\(.number) \(.html_url)"'
          ;;
        *) usage ;;
      esac
    '';
  };
in
{
  environment.systemPackages = [ github-issue ];

  openclaw.skills.github-issues = ./skills/github-issues;
  openclaw.commands = [ github-issue ];
}
