#!/usr/bin/env bash
#
# Build md_patcher.ko for every kernel published in the latest pox-begonia-kernel
# release and drop the modules into data/begonia/.
#
# Each release asset is named   Pox-<ver>-<Edition>-<commit>-begonia.zip
# and the kernel's `uname -r` is exactly   <base>-Pox-<ver>-<Edition>-<commit>
# where <base> is the pox kernel base version (e.g. 4.14.357).  Because the
# module only needs a matching vermagic, every asset is built from a single
# tree (POX_REF) with LOCALVERSION set to the asset's release suffix.
#
# Usage:
#   tools/build_pox_modules.sh
#
# Environment:
#   POX_REPO   git URL               (default: https://github.com/pox-project/pox-begonia-kernel)
#   POX_REF    branch to build from  (default: onyx)
#   DEFCONFIG  defconfig to build    (default: begonia_user_defconfig)
#   EXCLUDE    asset-name regex to skip (default: ReSukiSU|Kaeru)
#   WORK       scratch dir           (default: <repo>/.work)
#   GH_TOKEN   optional GitHub token for API rate limits
#
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
ROOT="$(cd "$SCRIPT_DIR/.." && pwd)"

POX_REPO="${POX_REPO:-https://github.com/POX-project/pox-begonia-kernel}"
POX_REF="${POX_REF:-onyx}"
DEFCONFIG="${DEFCONFIG:-begonia_user_defconfig}"
EXCLUDE="${EXCLUDE:-ReSukiSU|Kaeru}"
WORK="${WORK:-$ROOT/.work}"
POX_DIR="$WORK/pox"
RELEASE_JSON="$WORK/release.json"
DEST="$ROOT/data/begonia"

log() { printf '[pox-modules] %s\n' "$*"; }

mkdir -p "$WORK" "$DEST"

# 1. Ensure the pox tree is present.
if [ ! -d "$POX_DIR/.git" ]; then
    log "cloning $POX_REPO"
    git clone --filter=blob:none "$POX_REPO" "$POX_DIR"
fi
cd "$POX_DIR"
git remote set-url origin "$POX_REPO"
git fetch -q origin "$POX_REF"
git checkout -q -f "refs/remotes/origin/$POX_REF"

# 2. Bootstrap the toolchain.
if [ ! -x "$POX_DIR/kerdevdep/clang/bin/clang" ]; then
    log "bootstrapping kerdevdep"
    bash "$POX_DIR/kerdevdep/setup_kerdevdep.sh"
fi
# shellcheck disable=SC1091
source "$POX_DIR/kerdevdep/env.sh"

BASE="$(make -s kernelversion)"
log "pox base kernel version: $BASE"

# 3. Fetch the latest release asset list.
API="https://api.github.com/repos/POX-project/pox-begonia-kernel/releases/latest"
curl_args=(-fsSL -H "Accept: application/vnd.github+json")
[ -n "${GH_TOKEN:-}" ] && curl_args+=(-H "Authorization: Bearer $GH_TOKEN")
if ! curl "${curl_args[@]}" "$API" -o "$RELEASE_JSON"; then
    log "failed to fetch release metadata"
    exit 1
fi

mapfile -t ASSET_BASES < <(python3 - "$RELEASE_JSON" <<'PY'
import json, sys
data = json.load(open(sys.argv[1]))
bases = {a["name"][:-len("-begonia.zip")] for a in data.get("assets", [])
         if a["name"].endswith("-begonia.zip")}
print("\n".join(sorted(bases)))
PY
)

if [ "${#ASSET_BASES[@]}" -eq 0 ]; then
    log "no kernel assets found in latest release"
    exit 1
fi

# 4. Build a module for every asset whose release string is not bundled yet.
added=0
for asset_base in "${ASSET_BASES[@]}"; do
    if [ -n "$EXCLUDE" ] && printf '%s\n' "$asset_base" | grep -Eq "$EXCLUDE"; then
        log "skip (excluded): $asset_base"
        continue
    fi

    release="$BASE-$asset_base"
    ko="$DEST/md_patcher-$release.ko"
    if [ -f "$ko" ]; then
        log "present: $release"
        continue
    fi

    suffix="${release#"$BASE"}"
    log "building: $release"
    POX_DIR="$POX_DIR" bash "$ROOT/tools/build_module.sh" \
        "$POX_REF" "$suffix" "$DEFCONFIG" "$ko.tmp"
    mv -f "$ko.tmp" "$ko"
    added=$((added + 1))
done

log "$added new module(s) added to data/begonia"
