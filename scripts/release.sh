#!/bin/zsh
set -euo pipefail

root="${0:A:h:h}"
app="OddFrog"
dest="${DEST:-/Applications}/$app.app"
sign="${SIGN:--}"

cd "$root"
make bundle SIGN="$sign"

if pgrep -x "$app" >/dev/null; then
  osascript -e "tell application \"$app\" to quit" >/dev/null 2>&1 || pkill -x "$app" || true
  while pgrep -x "$app" >/dev/null; do sleep 0.2; done
fi

mkdir -p "${dest:h}"
rsync -a --delete "build/$app.app/" "$dest/"
codesign --verify --deep --strict "$dest"

if [[ "${LAUNCH:-1}" == "1" ]]; then
  open "$dest"
fi

echo "Installed $dest"
