# The fixed clean-up pulse's mac-free-disk reflex runs on a Mac under its free-disk floor: caches, Homebrew's old
# downloads, Nix garbage and profile generations older than 14 days and Trash items trashed over 7 days ago, never
# documents, projects or anything else; the kanban runner's cached runner.js, its copy for when the hub is away, stays.
set -u
volume=/System/Volumes/Data
[ -d "$volume" ] || volume=/
free() { df -Pk "$volume" | awk 'NR == 2 { printf "%.1f GB of %.0f GB, %.0f%%", $4 / 1048576, $2 / 1048576, 100 * $4 / $2 }'; }
ratio() { df -Pk "$volume" | awk 'NR == 2 { printf "%d", 100 * $4 / $2 }'; }
if [ "$(ratio)" -ge @floor@ ]; then
  echo "skip $(free)"
  exit 0
fi
echo "before $(free)"
for dir in "$HOME/Library/Caches" "$HOME/.cache"; do
  [ -d "$dir" ] && [ ! -L "$dir" ] && find "$dir" -mindepth 1 -maxdepth 1 ! -name kanban-runner ! -name kanban -exec rm -rf {} + 2> /dev/null
done
for brew in /opt/homebrew/bin/brew /usr/local/bin/brew; do
  [ -x "$brew" ] && { "$brew" cleanup --prune=14 > /dev/null 2>&1; break; }
done
gc=/nix/var/nix/profiles/default/bin/nix-collect-garbage
[ -x "$gc" ] && "$gc" --delete-older-than 14d > /dev/null 2>&1
[ -d "$HOME/.Trash" ] && find "$HOME/.Trash" -mindepth 1 -maxdepth 1 -ctime +7 -exec rm -rf {} + 2> /dev/null
echo "after $(free)"
