#!/bin/bash
# watch.sh — watch scripts/ for changes and sync to the notebook pod automatically
set -euo pipefail

SCRIPTS_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
UPLOAD="$SCRIPTS_DIR/upload.sh"

echo "Watching $SCRIPTS_DIR for changes..."
echo "Press Ctrl+C to stop."
echo ""

if command -v inotifywait &>/dev/null; then
    while inotifywait -q -r -e close_write,create,delete "$SCRIPTS_DIR" \
          --exclude '\.swp$|\.swx$|~$|__pycache__'; do
        echo "[$(date +%H:%M:%S)] Change detected — syncing..."
        bash "$UPLOAD" && echo "  sync OK"
    done
else
    # Fallback: poll every 3 seconds using checksum
    last=""
    while true; do
        current=$(find "$SCRIPTS_DIR" -type f | sort | xargs md5sum 2>/dev/null | md5sum)
        if [ "$current" != "$last" ]; then
            echo "[$(date +%H:%M:%S)] Change detected — syncing..."
            bash "$UPLOAD" && echo "  sync OK"
            last="$current"
        fi
        sleep 3
    done
fi
