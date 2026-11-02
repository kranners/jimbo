# Runs in butler's memory checkout. Prints the lines of core and the journal,
# newest day first, that contain any of the words given, so the voice lane can
# answer from memory in one quick call. history/ is left out on purpose: it
# holds the long training log, which the voice lane never reads out.

if [ $# -lt 1 ] || [ $# -gt 6 ]; then
  echo "usage: memory-recall <word> [word...]  (one to six words, any of which may match)" >&2
  exit 2
fi

patterns=()
for word in "$@"; do
  if [ "${#word}" -lt 2 ] || [ "${#word}" -gt 40 ]; then
    echo "memory-recall: each word is 2 to 40 characters" >&2
    exit 2
  fi
  patterns+=(-e "$word")
done

shopt -s nullglob
journal=(journal/*.md)
files=(core/*.md)
for ((i = ${#journal[@]} - 1; i >= 0; i--)); do
  files+=("${journal[$i]}")
done

found=$({ grep --ignore-case --fixed-strings --with-filename --no-messages "${patterns[@]}" -- "${files[@]}" || true; } | head -n 40)
if [ -z "$found" ]; then
  echo "Nothing in memory mentions $*."
else
  printf '%s\n' "$found" | cut -c 1-400
fi
