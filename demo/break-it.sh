#!/usr/bin/env bash
# Demo prop for "Den røde testen".
#
# Flips one character in the Norwegian greeting template: "Hei, {0}!" -> "Hei {0}!".
# It looks like a harmless copy tweak and it breaks three tests, which is exactly the
# point - you did not have to notice, the pipeline noticed.
#
#   ./demo/break-it.sh break    apply the change
#   ./demo/break-it.sh fix      put the comma back
#   ./demo/break-it.sh status   show which state the file is in
set -euo pipefail

FILE="$(cd "$(dirname "$0")/.." && pwd)/app/src/DemoApi/Features/Greeting.cs"
GOOD='["nb"] = "Hei, {0}!",'
BAD='["nb"] = "Hei {0}!",'

case "${1:-status}" in
  break)
    grep -qF "$GOOD" "$FILE" || { echo "Already broken (or the file changed)."; exit 1; }
    # Use a temp file rather than sed -i: the -i flag differs between GNU and BSD sed.
    awk -v good="$GOOD" -v bad="$BAD" 'index($0, good) { sub(/Hei, \{0\}!/, "Hei {0}!") } { print }' \
      "$FILE" > "$FILE.tmp" && mv "$FILE.tmp" "$FILE"
    echo "Broken. Commit this on a branch, open a PR, and let CI go red."
    ;;
  fix)
    grep -qF "$BAD" "$FILE" || { echo "Already correct."; exit 1; }
    awk -v bad="$BAD" 'index($0, bad) { sub(/Hei \{0\}!/, "Hei, {0}!") } { print }' \
      "$FILE" > "$FILE.tmp" && mv "$FILE.tmp" "$FILE"
    echo "Fixed. Push to the same branch and watch the pipeline rerun by itself."
    ;;
  status)
    if grep -qF "$GOOD" "$FILE"; then echo "Correct: tests should pass."
    elif grep -qF "$BAD" "$FILE"; then echo "Broken: 3 tests should fail."
    else echo "Neither state found - has the file been edited?"; exit 1; fi
    ;;
  *)
    echo "Usage: $0 {break|fix|status}"; exit 1 ;;
esac
