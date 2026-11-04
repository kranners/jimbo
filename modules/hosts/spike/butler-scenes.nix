{
  config,
  lib,
  pkgs,
  ...
}:
let
  inherit (config.users.users.butler) home;
  inherit (config.butler.scenes) dir catalog;

  # Each picture made with `imagine` that Aaron kept, by the outbox file it came from, copied once into spike's state.
  # None is committed here: jimbo is public, the Skynet ones are Bloom's branding, and a cloud session cannot read butler's outbox.
  sources = lib.concatMap (
    group: lib.mapAttrsToList (name: scene: scene // { inherit group name; }) catalog.${group}
  ) (lib.attrNames catalog);

  importScenes =
    pkgs.writers.writePython3 "butler-scenes-import"
      {
        libraries = [ pkgs.python3Packages.pillow ];
        flakeIgnore = [ "E501" ];
      }
      ''
        import json
        import os
        import sys
        from PIL import Image

        outbox, root = sys.argv[1], sys.argv[2]
        missing = 0
        with open(sys.argv[3]) as scenes:
            catalog = json.load(scenes)
        for scene in catalog:
            target = os.path.join(root, scene["group"], scene["name"] + ".webp")
            if os.path.exists(target):
                continue
            source = os.path.join(outbox, scene["source"])
            if not os.path.isfile(source):
                print(f"{scene['group']}/{scene['name']}: {scene['source']} is not in the outbox", file=sys.stderr)
                missing += 1
                continue
            os.makedirs(os.path.dirname(target), exist_ok=True)
            with Image.open(source) as image:
                image = image.convert("RGB")
                image.thumbnail((1536, 1024))
                image.save(target + ".tmp", "WEBP", quality=80, method=6)
            os.chmod(target + ".tmp", 0o640)
            os.replace(target + ".tmp", target)
            print(f"{scene['group']}/{scene['name']}: imported from {scene['source']}")
        print(f"{missing} scene(s) missing" if missing else "every scene is in place")
      '';
in
{
  options.butler.scenes = {
    dir = lib.mkOption {
      type = lib.types.str;
      default = "/var/lib/butler-scenes";
      description = "Where butler's scene pictures live on spike, one folder per group, outside every repository.";
    };
    catalog = lib.mkOption {
      type = lib.types.attrsOf (
        lib.types.attrsOf (
          lib.types.submodule {
            options = {
              source = lib.mkOption {
                type = lib.types.str;
                description = "The file in butler's outbox the picture is imported from.";
              };
              use = lib.mkOption {
                type = lib.types.str;
                description = "When butler attaches it.";
              };
            };
          }
        )
      );
      description = "Butler's scene pictures by group and name.";
    };
  };

  config = {
    butler.scenes.catalog = import ./butler-scenes-catalog.nix;

    # Reads the outbox as butler, so it never follows a link of butler's as root, and writes nothing else.
    systemd.services.butler-scenes-import = {
      description = "Copy butler's scene pictures from its outbox into spike's state";
      wantedBy = [ "multi-user.target" ];
      before = [ "butler.service" ];
      serviceConfig = {
        Type = "oneshot";
        User = "butler";
        Group = "butler";
        StateDirectory = lib.removePrefix "/var/lib/" dir;
        StateDirectoryMode = "0750";
        ExecStart = "${importScenes} ${home}/outbox ${dir} ${pkgs.writeText "butler-scenes.json" (builtins.toJSON sources)}";
        PrivateNetwork = true;
        ProtectSystem = "strict";
        ProtectHome = true;
        PrivateTmp = true;
        NoNewPrivileges = true;
        ReadOnlyPaths = [ "${home}/outbox" ];
      };
    };

    systemd.services.butler.serviceConfig.BindReadOnlyPaths = [ "-${dir}" ];
  };
}
