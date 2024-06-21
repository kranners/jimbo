#!/nix/store/agkxax48k35wdmkhmmija2i2sxg8i7ny-bash-5.2p26/bin/bash
set -o errexit
set -o nounset
set -o pipefail

export PATH="/nix/store/8wyfyqrsnysdpy7yf6kih1pzh38ylz9w-download-wallpapers/bin:/nix/store/xp4532njypv3n742rgwb0z240xqgkr6d-swaybg-1.2.1/bin:/nix/store/1j5alv78jbcc4kfhy1rx4h5b8x423ain-busybox-1.36.1/bin:$PATH"

echo "Downloading..."
WALLPAPER_PATH="$(download-wallpapers)" 

echo "WALLPAPER_PATH=$WALLPAPER_PATH"
OLD_PIDS="$(pgrep swaybg || true)"
echo "OLD_PIDS=$OLD_PIDS"

swaybg -i "$WALLPAPER_PATH" &
echo "\$?=$?"

for PID in $OLD_PIDS; do
  [[ -n "$PID" ]] && kill "$PID" && echo "KILLED $PID"
done

