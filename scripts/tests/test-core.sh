#!/bin/zsh

set -euo pipefail

test_dir=${0:A:h}
scripts_dir=${test_dir:h}
slugify="$scripts_dir/lib/slugify.pl"
project=$(/usr/bin/mktemp -d "${TMPDIR:-/tmp}/nicolasfurno-core-test.XXXXXX")
trap '/bin/rm -rf -- "$project"' EXIT INT TERM
/bin/mkdir -p "$project/content/test"

assert_slug() {
  local input=$1 expected=$2 mode=${3:-propose} actual
  actual=$(print -rn -- "$input" | "$slugify" "$mode")
  [[ $actual == $expected ]] || {
    print -u2 "Slug incorrect : « $input » donne « $actual » au lieu de « $expected »."
    exit 1
  }
}

# Chaque assertion correspond à une règle du normaliseur, pas à un titre réel.
assert_slug 'Titre accentué' 'titre-accentue'
assert_slug 'The Exemple avec des mots' 'exemple-mots'
assert_slug "L’exemple d’une élision" 'exemple-elision'
assert_slug "Author’s Work" 'authors-work'
assert_slug 'Série 2 TV' 'serie-2-tv'
assert_slug 'Le' 'le'
assert_slug 'The slug corrigé +' 'the-slug-corrige' sanitize
if print -rn -- '!!!' | "$slugify" >/dev/null 2>&1; then
  print -u2 'Une entrée vide après normalisation aurait dû être refusée.'
  exit 1
fi

ARTICLE_ROOT=$project source "$scripts_dir/lib/article.sh"
created=$(article_create test 'bundle-test' 'Titre "test"' $'id: 42\n')
article_set_frontmatter "$created" image 'image test.jpg'
[[ -f $created ]]
/usr/bin/grep -q '^title: "Titre \\"test\\""$' "$created"
/usr/bin/grep -q '^id: 42$' "$created"
/usr/bin/grep -q '^image: "image test.jpg"$' "$created"
[[ $(article_surnames 'Prénom Nom, Autre Personne') == 'Nom, Personne' ]]
[[ $(article_join alpha beta gamma) == 'alpha, beta, gamma' ]]

malformed="$project/malformed.md"
print -r -- 'sans front matter' > "$malformed"
if article_set_frontmatter "$malformed" image test >/dev/null 2>&1; then
  print -u2 'Un article sans front matter final aurait dû être refusé.'
  exit 1
fi

[[ $(article_find_existing test id 42) == $created ]]
[[ $(article_find_existing test id 42 saison __absent__) == $created ]]
[[ -z $(article_find_existing test id 42 saison '[1]') ]]
qualified=$(article_create test 'bundle-qualifie' 'Titre qualifié' $'id: 43\nsaison: [1,2]\n')
[[ $(article_find_existing test id 43 saison '[1, 2]') == $qualified ]]
[[ -z $(article_find_existing test id 43 saison '[2]') ]]

print 'Tests du noyau réussis.'
