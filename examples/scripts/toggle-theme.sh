#!/bin/bash

# @raycast.schemaVersion 1
# @raycast.title Toggle Theme
# @raycast.mode silent
# @raycast.icon 🌗
# @raycast.packageName System
# @raycast.argument1 { "type": "text", "placeholder": "light or dark", "optional": true }

set -euo pipefail

want=$(printf '%s' "${1:-}" | tr '[:upper:]' '[:lower:]' | tr -d '[:space:]')

case "$want" in
    ""|toggle|t) target="not dark mode" ;;
    light|l) target="false" ;;
    dark|d) target="true" ;;
    *)
        printf 'Unknown appearance "%s". Use light, dark, or no argument to toggle.\n' "$1" >&2
        exit 1
        ;;
esac

if ! state=$(osascript <<APPLESCRIPT
tell application "System Events"
    tell appearance preferences
        set dark mode to $target
        return dark mode
    end tell
end tell
APPLESCRIPT
); then
    printf 'Allow Odd Frog to control System Events in System Settings > Privacy & Security > Automation.\n' >&2
    exit 1
fi

if [ "$state" = "true" ]; then
    printf 'Dark\n'
else
    printf 'Light\n'
fi
