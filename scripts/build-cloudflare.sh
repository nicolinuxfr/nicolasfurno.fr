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

JPEGTRAN_BIN="$(command -v jpegtran || true)"

if [ -z "$JPEGTRAN_BIN" ]; then
  LIBJPEG_TURBO_VERSION="3.2.0"
  LIBJPEG_TURBO_SHA256="21297da4a4eb34ebefc54afca5d8dd86c0fdd6a9dfe49b1b962c5d1eeeafd8ec"
  LIBJPEG_TURBO_DIR="$PWD/.cache/libjpeg-turbo-$LIBJPEG_TURBO_VERSION"
  LIBJPEG_TURBO_PACKAGE="$PWD/.cache/libjpeg-turbo-$LIBJPEG_TURBO_VERSION.deb"
  JPEGTRAN_BIN="$LIBJPEG_TURBO_DIR/opt/libjpeg-turbo/bin/jpegtran"

  if [ "$(uname -s)" != "Linux" ] || [ "$(uname -m)" != "x86_64" ]; then
    echo "jpegtran is required to optimize JPEG files on this platform." >&2
    exit 1
  fi

  if [ ! -x "$JPEGTRAN_BIN" ]; then
    echo "Downloading libjpeg-turbo $LIBJPEG_TURBO_VERSION..."
    mkdir -p "$PWD/.cache"
    curl \
      --fail \
      --location \
      --silent \
      --show-error \
      --output "$LIBJPEG_TURBO_PACKAGE" \
      "https://github.com/libjpeg-turbo/libjpeg-turbo/releases/download/$LIBJPEG_TURBO_VERSION/libjpeg-turbo-official_${LIBJPEG_TURBO_VERSION}_amd64.deb"
    printf '%s  %s\n' "$LIBJPEG_TURBO_SHA256" "$LIBJPEG_TURBO_PACKAGE" | sha256sum --check --status
    dpkg-deb --extract "$LIBJPEG_TURBO_PACKAGE" "$LIBJPEG_TURBO_DIR"
  fi

  LIBJPEG_TURBO_LIB="$LIBJPEG_TURBO_DIR/opt/libjpeg-turbo/lib64"
  export LD_LIBRARY_PATH="$LIBJPEG_TURBO_LIB${LD_LIBRARY_PATH:+:$LD_LIBRARY_PATH}"
fi

echo "Optimizing JPEG files without quality loss..."
JPEGTRAN_BIN="$JPEGTRAN_BIN" node scripts/optimize-jpegs.mjs public

echo "Building the Pagefind search index..."
npx pagefind
