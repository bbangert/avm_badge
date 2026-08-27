#!/usr/bin/env bash
# Build firmware/assets.avm from the frames and fonts the device reads at runtime.
set -euo pipefail
root="$(cd "$(dirname "$0")/../.." && pwd)"
pb="$root/AtomVM/build/tools/packbeam/packbeam"
stage="$(mktemp -d)"
trap 'rm -rf "$stage"' EXIT

mkdir -p "$stage/assets/priv/rickroll" "$stage/assets/priv/fonts"
cp "$root"/firmware/assets/rickroll/*.rgba "$stage/assets/priv/rickroll/"
cp "$root"/firmware/assets/fonts/*.uf "$stage/assets/priv/fonts/"
( cd "$stage" && "$pb" create -l "$root/firmware/assets.avm" \
    assets/priv/rickroll/*.rgba assets/priv/fonts/*.uf )
ls -l "$root/firmware/assets.avm"
