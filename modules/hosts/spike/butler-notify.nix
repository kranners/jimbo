{ pkgs, ... }:
let
  spool = "/var/lib/butler-notify";
  group = "butler-notify";

  butler-notify = pkgs.writeShellApplication {
    name = "butler-notify";
    runtimeInputs = [
      pkgs.coreutils
      pkgs.jq
    ];
    text = ''
      usage() {
        echo "usage: butler-notify [file...] <<'EOF' the message EOF  (sends Aaron a Discord DM from butler)" >&2
        exit 2
      }

      text=$(cat)
      [ -n "''${text//[[:space:]]/}" ] || [ "$#" -gt 0 ] || usage
      [ "$#" -le 10 ] || { echo "butler-notify: Discord takes at most 10 files" >&2; exit 2; }

      id="$(date +%Y%m%d-%H%M%S)-$$"
      names=()
      for file in "$@"; do
        [ -f "$file" ] || { echo "butler-notify: $file is not a file" >&2; exit 2; }
        name="$id-$(basename "$file")"
        [[ "$name" != *.json ]] || name="$name.txt"
        install -m 0640 "$file" "${spool}/$name"
        names+=("$name")
      done

      jq -n --arg text "$text" '{text: $text, files: $ARGS.positional}' --args "''${names[@]}" > "${spool}/$id.json.tmp"
      chmod 0640 "${spool}/$id.json.tmp"
      mv "${spool}/$id.json.tmp" "${spool}/$id.json"
      echo "Queued notice $id; butler sends it within 5 seconds."
    '';
  };
in
{
  users.groups.${group} = { };
  users.users.butler.extraGroups = [ group ];
  users.users.aaron.extraGroups = [ group ];

  systemd.tmpfiles.rules = [ "d ${spool} 2770 root ${group} -" ];

  environment.systemPackages = [ butler-notify ];

  systemd.services.butler = {
    environment.DISCORD_NOTIFY_DIR = spool;
    serviceConfig.BindPaths = [ spool ];
  };
}
