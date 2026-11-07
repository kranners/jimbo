{ host, pkgs, ... }:
let
  # The gates' script against a scratch runner.json, with the store's own mode 444 gates files.
  gates =
    name: value:
    import ./gates.nix {
      inherit pkgs;
      configDir = "$TMPDIR/config";
      gatesFile = pkgs.writeText "backlogic-runner-gates-${name}.json" (builtins.toJSON value);
    };
  first = gates "first" {
    sessions = 6;
    peerCloudClaims = 1;
  };
  second = gates "second" {
    sessions = 64;
    peerCloudClaims = 0;
  };
  third = gates "third" {
    sessions = 64;
    peerCloudClaims = 0;
    accountCeilings = {
      cloud-work-2.sevenDayLimit = 0.95;
      cloud-work-9.sevenDayLimit = 0.95;
      learned.sevenDayLimit = 0.95;
    };
  };
in
{
  # Options only, off by default: spike runs backlogic's runner with them, and the NUC can once its role is on.
  nixosSystemModule.imports = [ ./runner.nix ];

  # A change of the gates rewrites runner.json and its stamp, as the second run on spike once failed to.
  checks.${host.system}.backlogic-runner-gates =
    pkgs.runCommand "backlogic-runner-gates-test" { nativeBuildInputs = [ pkgs.jq ]; }
      ''
        export STATE_DIRECTORY=$TMPDIR/state
        mkdir -p $TMPDIR/config $STATE_DIRECTORY
        echo '{"accounts":[1],"sessions":2}' > $TMPDIR/config/runner.json
        ${pkgs.lib.getExe first}
        [ "$(jq -c . $TMPDIR/config/runner.json)" = '{"accounts":[1],"sessions":6,"peerCloudClaims":1}' ]
        # The stamp an older script left, a copy of the store's file with its mode 444.
        chmod 444 $STATE_DIRECTORY/applied.json
        ${pkgs.lib.getExe second}
        [ "$(jq -c . $TMPDIR/config/runner.json)" = '{"accounts":[1],"sessions":64,"peerCloudClaims":0}' ]
        [ "$(stat -c %a $STATE_DIRECTORY/applied.json)" = 644 ]
        # The gates unchanged, an owner's edit holds.
        jq '.sessions = 3' $TMPDIR/config/runner.json > $TMPDIR/edited && mv $TMPDIR/edited $TMPDIR/config/runner.json
        ${pkgs.lib.getExe second} | grep -q 'already the module'
        [ "$(jq .sessions $TMPDIR/config/runner.json)" = 3 ]
        [ -z "$(ls -A $STATE_DIRECTORY | grep -v '^applied.json$')" ]
        # An account's ceilings merge into that account alone, its other settings kept.
        # One with a learned reserve, which refuses them, and one missing are named and left alone.
        echo '{"sessions":64,"accounts":[{"name":"personal","sevenDayLimit":1},{"name":"cloud-work-2","sevenDayPacing":1,"sevenDayLimit":0.8},{"name":"learned","reserve":"learned"}]}' > $TMPDIR/config/runner.json
        ${pkgs.lib.getExe third} 2>$TMPDIR/skipped
        [ "$(jq -c .accounts $TMPDIR/config/runner.json)" = '[{"name":"personal","sevenDayLimit":1},{"name":"cloud-work-2","sevenDayPacing":1,"sevenDayLimit":0.95},{"name":"learned","reserve":"learned"}]' ]
        grep -q 'account cloud-work-9 is not' $TMPDIR/skipped
        grep -q 'account learned is not' $TMPDIR/skipped
        [ "$(jq 'has("accountCeilings")' $TMPDIR/config/runner.json)" = false ]
        touch $out
      '';
}
