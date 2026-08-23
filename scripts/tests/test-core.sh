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
[[ $(people_name 'John Francis Daley') == $'John Francis\u00a0Daley' ]]
[[ $(people_name 'Guillermo del Toro') == $'Guillermo del\u00a0Toro' ]]
[[ $(people_join_names 'Jane Campion') == $'Jane\u00a0Campion' ]]
[[ $(people_join_names 'Daniel Scheinert' 'Daniel Kwan') == $'Daniel\u00a0Scheinert et Daniel\u00a0Kwan' ]]
[[ $(people_join_names 'Joaquim Dos Santos' 'Justin K. Thompson' 'Kemp Powers') == $'Joaquim Dos\u00a0Santos, Justin K.\u00a0Thompson et Kemp\u00a0Powers' ]]
[[ $(people_split_credits 'Rodolphe Burger, Sofiane Saidi & Mehdi Haddab') == $'Rodolphe Burger\nSofiane Saidi\nMehdi Haddab' ]]
westernized=$(people_westernize_tmdb \
  '{"created_by":[{"id":1,"name":"大友啓史","original_name":"大友啓史"}],"networks":[{"id":1,"name":"日本"}]}' \
  '{"created_by":[{"id":1,"name":"Keishi Otomo","original_name":"大友啓史"}],"networks":[{"id":1,"name":"Japan"}]}')
[[ $(print -r -- "$westernized" | jq -r '.created_by[0].name') == 'Keishi Otomo' ]]
[[ $(print -r -- "$westernized" | jq -r '.networks[0].name') == '日本' ]]

source "$scripts_dir/lib/tmdb.sh"
[[ $(tmdb_singular_query '10dances') == '10dance' ]]
[[ $(tmdb_singular_query '10 Dance') == '10 Dance' ]]
merged=$(tmdb_merge_search_results \
  '{"page":1,"results":[{"id":1},{"id":2}]}' \
  '{"page":1,"results":[{"id":1},{"id":3}]}')
[[ $(print -r -- "$merged" | jq -c '[.results[].id]') == '[1,2,3]' ]]
request() {
  case $3 in
    query=10dances) print -r -- '{"page":1,"results":[]}' ;;
    query=10dance) print -r -- '{"page":1,"results":[{"id":1400032}]}' ;;
    *) return 1 ;;
  esac
}
fallback=$(tmdb_search_response test search/movie 10dances)
unfunction request
[[ $(print -r -- "$fallback" | jq -r '.results[0].id') == 1400032 ]]

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
