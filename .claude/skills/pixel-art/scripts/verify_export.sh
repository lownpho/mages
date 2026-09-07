#!/usr/bin/env bash
# verify_export.sh — place a working .ase in this project's asset_src tree,
# run its real export pipeline on just that path, and diff the shipped PNG
# against the reference PNG the .ase was built from. Proves the round-trip
# is pixel-identical instead of assuming it.
#
# Collapses the manual dance (mkdir, cp, run export_assets.lua, cat the meta
# json, hand-write a pixel-diff) into one call, done once per sprite instead
# of retyped per sprite.
#
# Usage:
#   verify_export.sh <repo_root> <rel_path> <name> <source_ase> <reference_png>
#
#   repo_root      path containing asset_src/export_assets.lua and game/
#   rel_path       path relative to asset_src/graphics/ and game/, e.g.
#                  characters/enemies/thornthrower
#   name           file basename without extension, e.g. thornthrower
#   source_ase     the .ase to install (e.g. produced by import_multi_tag.lua)
#   reference_png  the working sheet PNG the .ase's frames came from
#
# Exits non-zero if the export fails or the shipped PNG isn't pixel-identical
# to reference_png.

set -euo pipefail

if [ "$#" -ne 5 ]; then
  echo "usage: verify_export.sh <repo_root> <rel_path> <name> <source_ase> <reference_png>" >&2
  exit 2
fi

repo_root=$1
rel_path=$2
name=$3
source_ase=$4
reference_png=$5

dest_dir="$repo_root/asset_src/graphics/$rel_path"
dest_ase="$dest_dir/$name.ase"
mkdir -p "$dest_dir"
cp "$source_ase" "$dest_ase"

rm -rf "${repo_root:?}/asset_src/meta/$rel_path"
( cd "$repo_root" && aseprite -b --script-param paths="$rel_path" --script asset_src/export_assets.lua )

shipped_png="$repo_root/game/$rel_path/$name.png"
if [ ! -f "$shipped_png" ]; then
  echo "FAIL: export did not produce $shipped_png" >&2
  exit 1
fi

python3 - "$reference_png" "$shipped_png" <<'PY'
import sys
from PIL import Image
import numpy as np

ref_path, shipped_path = sys.argv[1], sys.argv[2]
a = Image.open(ref_path).convert("RGBA")
b = Image.open(shipped_path).convert("RGBA")
if a.size != b.size:
    print(f"FAIL: size mismatch, reference={a.size} shipped={b.size}")
    sys.exit(1)
if not (np.array(a) == np.array(b)).all():
    print("FAIL: pixel mismatch between reference and shipped export")
    sys.exit(1)
print(f"OK: {shipped_path} pixel-identical to {ref_path} ({a.size[0]}x{a.size[1]})")
PY
