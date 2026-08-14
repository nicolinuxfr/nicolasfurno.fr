#!/bin/sh

set -eu

if [ "$(git rev-parse --is-shallow-repository)" = "true" ]; then
  echo "Fetching complete Git history without historical file contents..."
  git fetch --unshallow --filter=blob:none
fi

if [ ! -f "$PWD/hugo.toml" ] || [ ! -f "$PWD/package.json" ]; then
  echo "Run this script from the project root." >&2
  exit 1
fi

PUBLIC_DIR="$PWD/public"
echo "Removing the previous generated site..."
rm -rf -- "$PUBLIC_DIR"

echo "Building the site with Hugo..."
hugo \
  --minify \
  --enableGitInfo \
  --cacheDir="$PWD/.cache/hugo"

echo "Building the Pagefind search index..."
npx pagefind
