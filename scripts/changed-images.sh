#!/bin/sh
# Print the image names (directories under images/) to rebuild, as a JSON array.
#   scripts/changed-images.sh BASE_SHA     images changed between BASE_SHA and HEAD
#   scripts/changed-images.sh              all images
# A change under scripts/ or a workflow rebuilds everything; so does an unknown or all-zero base
# (first push of a branch).
set -eu
cd "$(dirname "$0")/.."
all=$(ls images)
base="${1:-}"
if [ -z "$base" ] || ! git cat-file -e "$base^{commit}" 2>/dev/null; then
  list=$all
else
  files=$(git diff --name-only "$base" HEAD)
  if printf '%s\n' "$files" | grep -Eq '^(scripts/|\.github/workflows/|\.gitea/workflows/)'; then
    list=$all
  else
    list=$(printf '%s\n' "$files" | sed -n 's#^images/\([^/]*\)/.*#\1#p' | sort -u)
  fi
fi
out=
for n in $list; do
  if [ -f "images/$n/Dockerfile" ]; then out="$out\"$n\","; fi
done
echo "[${out%,}]"
