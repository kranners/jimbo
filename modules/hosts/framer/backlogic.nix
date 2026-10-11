{ pkgs, ... }:
let
  url = "http://10.100.0.1:4200";
  tokenFile = "/var/lib/secrets/backlogic-token";

  backlogic-ticket = pkgs.writeShellApplication {
    name = "backlogic-ticket";

    runtimeInputs = [
      pkgs.curl
      pkgs.jq
    ];

    text = ''
      usage() {
        echo "usage: backlogic-ticket projects" >&2
        echo "       backlogic-ticket tickets <project>" >&2
        echo "       backlogic-ticket file <project> <title> <<'EOF' ... EOF  (text on stdin)" >&2
        exit 2
      }

      backlogic() {
        curl --silent --show-error --fail-with-body \
          --header "Authorization: Bearer $(cat ${tokenFile})" \
          --header "Content-Type: application/json" \
          "$@"
      }

      [ $# -ge 1 ] || usage

      case "$1" in
        projects)
          backlogic "${url}/api/snapshot" \
            | jq -r '.tickets | group_by(.project) | .[] | "\(.[0].project)\t\(map(select(.doneAt == null)) | length) open"'
          ;;
        tickets)
          [ $# -eq 2 ] || usage
          backlogic "${url}/api/snapshot" \
            | jq -r --arg project "$2" '.tickets[] | select(.project == $project and .doneAt == null) | "\(.id)\t\(.title)"'
          ;;
        file)
          [ $# -eq 3 ] || usage
          jq --null-input --arg project "$2" --arg title "$3" --rawfile text /dev/stdin \
            '{project: $project, title: $title, text: $text, assignee: "owner"}' \
            | backlogic --data @- "${url}/api/tickets" \
            | jq -r '.id'
          ;;
        *) usage ;;
      esac
    '';
  };
in
{
  environment.systemPackages = [ backlogic-ticket ];

  openclaw.skills.backlogic = ./skills/backlogic;
  openclaw.commands = [ backlogic-ticket ];
}
