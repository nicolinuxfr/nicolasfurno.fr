#!/bin/sh

set -eu

cd "$(dirname "$0")/.."

if [ ! -x node_modules/.bin/pagefind ]; then
  printf '\n→ Installation des dépendances\n'
  npm ci
fi

printf '\n→ Génération des pages de personnes\n'
npm run discover

printf '\n→ Préparation des anciennes affiches\n'
npm run legacy-posters

printf '\n→ Compilation du site avec Hugo\n'
hugo

printf '\n→ Indexation de la recherche avec Pagefind\n'
npm run index

printf '\n→ Démarrage du serveur de prévisualisation\n'
exec hugo server
