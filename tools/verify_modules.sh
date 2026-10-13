#!/usr/bin/env bash
#
# Check bundled md_patcher-*.ko vermagic.
#
# For the pox modules we maintain, the filename IS the target kernel's
# `uname -r`, so the vermagic must start with the filename. Legacy modules from
# the upstream tool use shortened filenames and are only informational here
# (they are loaded through the vermagic-checked vendor rc, not by exact name).
#
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
ROOT="$(cd "$SCRIPT_DIR/.." && pwd)"

fail=0
count=0
for f in "$ROOT"/data/*/md_patcher-*.ko; do
    [ -e "$f" ] || continue
    count=$((count + 1))
    name="$(basename "$f")"
    dev="$(basename "$(dirname "$f")")"
    rel="${name#md_patcher-}"
    rel="${rel%.ko}"

    vm="$(strings -a "$f" | grep -m1 '^vermagic=' | sed 's/^vermagic=//')"

    if [[ "$name" == *Pox-* ]]; then
        case "$vm" in
            "$rel "*) printf 'OK  %-8s %s\n' "$dev" "$rel" ;;
            *)        printf 'BAD %-8s %s\n    got: %s\n' "$dev" "$rel" "$vm"; fail=1 ;;
        esac
    else
        printf 'LEG %-8s %s\n    vermagic: %s\n' "$dev" "$rel" "$vm"
    fi
done

echo "---"
echo "$count module(s) checked"
exit "$fail"
