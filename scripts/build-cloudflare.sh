#!/bin/sh

set -eu

if [ "$(git rev-parse --is-shallow-repository)" = "true" ]; then
  echo "Fetching complete Git history without historical file contents..."
  git fetch --unshallow --filter=blob:none
fi

echo "Building the site with Hugo..."
hugo \
  --cleanDestinationDir \
  --minify \
  --enableGitInfo \
  --cacheDir="$PWD/.cache/hugo"

echo "Building the Pagefind search index..."
npx pagefind
