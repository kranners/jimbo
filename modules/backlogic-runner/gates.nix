# Merges the gates into runner.json as the instance does, a read, a change and a rename,
# and only when they differ from those it last wrote, so an owner's edit in Control Panel
# holds until the module's own values change.
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
    jq --slurpfile gates ${gatesFile} '. * $gates[0]' "$config" >"$tmp"
    chmod --reference="$config" "$tmp"
    before=$(jq -c '{sessions, loadPerCpu, memoryAvailableFloor, peerCloudClaims, sharedProjects}' "$config")
    mv "$tmp" "$config"
    install -m 0644 ${gatesFile} "$stampTmp"
    mv -f "$stampTmp" "$stamp"
    echo "runner.json's gates were $before, now $(cat ${gatesFile})"
  '';
}
