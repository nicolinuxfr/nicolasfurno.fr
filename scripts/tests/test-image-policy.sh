#!/bin/zsh

set -euo pipefail

test_dir=${0:A:h}
categories_dir=${test_dir:h}/categories
typeset -a image_writers

image_writers=("${(@f)$(
  /usr/bin/grep -El 'article_set_frontmatter.*[[:space:]]image([[:space:]]|$)|print .*image:' \
    "$categories_dir"/*.sh || true
)}")

if (( ${#image_writers} != 1 )) || [[ ${image_writers[1]:t} != photo.sh ]]; then
  print -u2 'Seule la catégorie photo doit écrire la métadonnée image.'
  print -u2 -l -- "${image_writers[@]}"
  exit 1
fi

print 'Politique de la métadonnée image vérifiée.'
