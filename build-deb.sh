#!/bin/bash
set -euo pipefail
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
cd "$SCRIPT_DIR"
for command in dpkg-buildpackage dh; do
    if ! command -v "$command" >/dev/null 2>&1; then
        printf 'Missing build tool: %s\n' "$command" >&2
        printf 'Install with: sudo apt install build-essential debhelper devscripts\n' >&2
        exit 1
    fi
done
chmod +x debian/rules
dpkg-buildpackage --build=binary --no-sign
mkdir -p dist
find .. -maxdepth 1 -type f -name 'atmiral_*.deb' -exec cp -v {} dist/ \;
printf 'Created debian package at: %s/dist/\n' "$SCRIPT_DIR"