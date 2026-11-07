# Merges the gates into runner.json as the instance does, a read, a change and a rename,
# and only when they differ from those it last wrote, so an owner's edit in Control Panel
# holds until the module's own values change.
# Its `accountCeilings`, account name to usage ceiling fields, merge into each named account
# of runner.json's `accounts` alone, leaving its other accounts and settings as they are,
# but never one whose reserve is `learned` or that has a `provider`, since backlogic refuses
# the ceilings on those, and it names any account it found nowhere or left alone.
# The stamp is written mode 644 through a rename, since a plain cp of the store's file kept
# its mode 444 and the next change of the gates failed to overwrite it.
{
  pkgs,
  configDir,
  gatesFile,
}:
pkgs.writeShellApplication {
  name = "backlogic-runner-gates";
  runtimeInputs = [
    pkgs.jq
    pkgs.coreutils
    pkgs.diffutils
  ];
  text = ''
    config="${configDir}/runner.json"
    stamp="$STATE_DIRECTORY/applied.json"
    if cmp -s ${gatesFile} "$stamp"; then
      echo "the gates in runner.json are already the module's: $(cat ${gatesFile})"
      exit 0
    fi
    tmp=""
    stampTmp=""
    trap 'rm -f "$tmp" "$stampTmp"' EXIT
    stampTmp=$(mktemp "$STATE_DIRECTORY/.applied.json.XXXXXX")
    tmp=$(mktemp "${configDir}/.runner.json.gates.XXXXXX")
    jq --slurpfile gates ${gatesFile} '
      ($gates[0].accountCeilings // {}) as $accounts
      | . * ($gates[0] | del(.accountCeilings))
      | .reserve as $reserve
      | if .accounts then .accounts |= map(
          if type == "object" and (.name | type) == "string" and (.provider | not)
            and (.reserve // $reserve // "ceilings") != "learned"
          then . + ($accounts[.name] // {}) else . end
        ) else . end
    ' "$config" >"$tmp"
    chmod --reference="$config" "$tmp"
    before=$(jq -c --slurpfile gates ${gatesFile} '
      ($gates[0].accountCeilings // {}) as $accounts
      | {sessions, loadPerCpu, memoryAvailableFloor, peerCloudClaims, sharedProjects}
      + {accountCeilings: ([.accounts[]? | objects | select((.name | type) == "string" and $accounts[.name] != null)
          | {(.name): {fiveHourCeiling, sevenDayPacing, sevenDayLimit}}] | add)}
    ' "$config")
    jq -r --slurpfile gates ${gatesFile} '
      .reserve as $reserve
      | [.accounts[]? | objects | select((.provider | not) and (.reserve // $reserve // "ceilings") != "learned") | .name] as $set
      | ($gates[0].accountCeilings // {}) | keys[] | select(. as $n | $set | index($n) | not)
      | "account \(.) is not in runner.json, or has a provider or a learned reserve, so its ceilings were not set"
    ' "$config" >&2
    mv "$tmp" "$config"
    install -m 0644 ${gatesFile} "$stampTmp"
    mv -f "$stampTmp" "$stamp"
    echo "runner.json's gates were $before, now $(cat ${gatesFile})"
  '';
}
