#!/usr/bin/env bash
# Tag a release, export the three builds straight into the website repo, push both.
# Usage: ./release.sh demo-v0.2.0
set -euo pipefail

TAG=${1:?usage: release.sh <tag>}
REPO=$(cd "$(dirname "$0")" && pwd)
SITE=$REPO/../lownpho.github.io/projects/mages

# The version stamped into the build comes from git describe, so the tree must be clean and tagged
# before anything is exported.
[[ -z $(git -C "$REPO" status --porcelain) ]] || { echo "working tree is dirty, commit first"; exit 1; }
git -C "$REPO" tag "$TAG"

timeout -s KILL 600 godot --headless --path "$REPO/game" --import
for preset in "Web" "Linux desktop" "Windows Desktop"; do
	timeout -s KILL 600 godot --headless --path "$REPO/game" --export-release "$preset"
done

cd "$SITE/builds"
bsdtar -a -cf mages-linux.zip mages.x86_64
bsdtar -a -cf mages-windows.zip mages.exe
rm mages.x86_64 mages.exe

git -C "$SITE" add -A .
git -C "$SITE" commit -m "Mages: $TAG"
git -C "$SITE" push
git -C "$REPO" push origin main "$TAG"
