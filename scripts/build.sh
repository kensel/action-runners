#!/bin/sh
# Build (and optionally test / push) runner images into one Docker Hub repository.
#
#   scripts/build.sh [--test] [--push] IMAGE...     IMAGE = a directory name under images/
#   scripts/build.sh --all [--test] [--push]
#
# Tags for images/<name> with TAG=<ver> in images/<name>/image.env:
#   $REPO:<name>-<ver>          pin this in workflows
#   $REPO:<name>-<ver>-<sha>    immutable, per commit
#   $REPO:<name>                moving "latest" for that image
#
# Env: REPO (default kensel/action-runners), GIT_SHA (default: git rev-parse HEAD).
set -eu
cd "$(dirname "$0")/.."
REPO="${REPO:-kensel/action-runners}"
GIT_SHA="${GIT_SHA:-$(git rev-parse HEAD 2>/dev/null || echo dev)}"
GIT_SHA=$(printf %.7s "$GIT_SHA")
test=; push=; images=
for a in "$@"; do
  case "$a" in
    --test) test=1 ;;
    --push) push=1 ;;
    --all) images="$images $(ls images)" ;;
    -*) echo "unknown option $a" >&2; exit 2 ;;
    *) images="$images $a" ;;
  esac
done
[ -n "$images" ] || { echo "usage: $0 [--test] [--push] (--all | IMAGE...)" >&2; exit 2; }

for name in $images; do
  dir="images/$name"
  [ -f "$dir/Dockerfile" ] || { echo "no $dir/Dockerfile" >&2; exit 2; }

  # image.env: TAG and PLATFORMS drive tagging; every other KEY=VALUE becomes a --build-arg.
  # Values may contain spaces (target lists), so the args are collected one per line.
  TAG=; PLATFORMS=linux/amd64; argfile=$(mktemp)
  while IFS= read -r line || [ -n "$line" ]; do
    case "$line" in ''|\#*) continue ;; esac
    key=${line%%=*}; val=${line#*=}
    case "$key" in
      TAG) TAG=$val ;;
      PLATFORMS) PLATFORMS=$val ;;
      *) printf '%s=%s\n' "$key" "$val" >> "$argfile" ;;
    esac
  done < "$dir/image.env"
  [ -n "$TAG" ] || { echo "$dir/image.env has no TAG" >&2; exit 2; }
  set --
  while IFS= read -r kv; do set -- "$@" --build-arg "$kv"; done < "$argfile"
  rm -f "$argfile"

  t_ver="$REPO:$name-$TAG"; t_sha="$REPO:$name-$TAG-$GIT_SHA"; t_latest="$REPO:$name"
  echo "::group::build $name -> $t_ver ($PLATFORMS)"
  # Reuse layers from the last published image when the Dockerfile has not changed them.
  docker pull -q "$t_latest" 2>/dev/null || true
  docker build --platform "$PLATFORMS" \
    --build-arg BUILDKIT_INLINE_CACHE=1 --cache-from "$t_latest" \
    --label "org.opencontainers.image.revision=$GIT_SHA" \
    --label "org.opencontainers.image.version=$name-$TAG" \
    "$@" -t "$t_ver" -t "$t_sha" -t "$t_latest" "$dir"
  echo "::endgroup::"

  if [ -n "$test" ] && [ -f "$dir/test.sh" ]; then
    echo "::group::test $name"
    docker run --rm -i "$t_ver" sh -s < "$dir/test.sh"
    echo "::endgroup::"
  fi
  if [ -n "$push" ]; then
    for t in "$t_ver" "$t_sha" "$t_latest"; do docker push "$t"; done
    echo "pushed $t_ver $t_sha $t_latest"
  fi
done
