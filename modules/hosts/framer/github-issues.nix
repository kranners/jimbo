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
        echo "       github-issue files <owner/repo> [path regex]" >&2
        echo "       github-issue read <owner/repo> <path>" >&2
        echo "       github-issue issues <owner/repo>" >&2
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
        files)
          [ $# -ge 2 ] || usage
          github "https://api.github.com/repos/$2/git/trees/HEAD?recursive=1" \
            | jq -r --arg pattern "''${3:-.}" '.tree[] | select(.type == "blob") | .path | select(test($pattern; "i"))'
          ;;
        read)
          [ $# -eq 3 ] || usage
          github "https://api.github.com/repos/$2/contents/$3" | jq -r '.content | gsub("\\n"; "") | @base64d'
          ;;
        issues)
          [ $# -eq 2 ] || usage
          github "https://api.github.com/repos/$2/issues?state=open&per_page=100" \
            | jq -r '.[] | select(.pull_request | not) | "#\(.number)\t\(.title)"'
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
