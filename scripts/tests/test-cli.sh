#!/bin/zsh

set -euo pipefail

test_dir=${0:A:h}
scripts_dir=${test_dir:h}
project=$(/usr/bin/mktemp -d "${TMPDIR:-/tmp}/nicolasfurno-cli-test.XXXXXX")
trap '/bin/rm -rf -- "$project"' EXIT INT TERM
/bin/mkdir -p "$project/content/film/existant" "$project/content/serie" "$project/content/photo" "$project/content/spectacle"
print 'baseURL = "https://example.test"' > "$project/hugo.toml"
print -- '---' > "$project/content/film/existant/index.md"
print -- '---' > "$project/content/spectacle/_index.md"

response=$(print '{}' | ARTICLE_ROOT="$project" "$scripts_dir/article-cli.sh" categories)
[[ $(print -r -- "$response" | jq -r '.ok') == true ]]
[[ $(print -r -- "$response" | jq -r '.data[0].id') == film ]]
[[ $(print -r -- "$response" | jq -r '.data[] | select(.id == "spectacle") | .label') == Spectacles ]]

before=$(/usr/bin/find "$project" -type f -print | /usr/bin/sort)
response=$(print '{"category":"spectacle","title":"Titre de test"}' | ARTICLE_ROOT="$project" "$scripts_dir/article-cli.sh" prepare)
[[ $(print -r -- "$response" | jq -r '.data.suggestedSlug') == titre-test ]]
after=$(/usr/bin/find "$project" -type f -print | /usr/bin/sort)
[[ $before == $after ]]

response=$(print '{"category":"serie","id":"42","label":"Série de test (2024)"}' | \
  HUGO_TMDB=test TMDB_FIXTURE_DIR="$test_dir/fixtures" ARTICLE_ROOT="$project" "$scripts_dir/article-cli.sh" prepare)
[[ $(print -r -- "$response" | jq -r '.data.label') == '*Série de test*, Test TV' ]]
[[ $(print -r -- "$response" | jq -r '.data.suggestedSlug') == serie-test-test-tv ]]
[[ $(print -r -- "$response" | jq -r '.data.details[] | select(.label == "Diffuseur") | .value') == 'Test TV' ]]
[[ $(print -r -- "$response" | jq -r '.data.seasons | length') == 2 ]]

response=$(print '{"category":"serie","id":"42","label":"Titre français (2024)"}' | \
  HUGO_TMDB=test TMDB_FIXTURE_DIR="$test_dir/fixtures" ARTICLE_ROOT="$project" "$scripts_dir/article-cli.sh" prepare)
[[ $(print -r -- "$response" | jq -r '.data.label') == '*Titre français*, Test TV' ]]
[[ $(print -r -- "$response" | jq -r '.data.suggestedSlug') == titre-francais-test-tv ]]

response=$(print '{"category":"film","id":"99","label":"Titre français (2024)"}' | \
  HUGO_TMDB=test TMDB_MOVIE_FIXTURE_DIR="$test_dir/fixtures" WIKIDATA_API_BASE_URL='http://127.0.0.1:1' \
  ARTICLE_ROOT="$project" "$scripts_dir/article-cli.sh" prepare)
[[ $(print -r -- "$response" | jq -r '.data.label') == '*Titre français*, Keishi Ohtomo' ]]
[[ $(print -r -- "$response" | jq -r '.data.suggestedSlug') == titre-francais-ohtomo ]]

response=$(print '{"category":"spectacle","title":"Titre de test","slug":"titre-test"}' | ARTICLE_ROOT="$project" "$scripts_dir/article-cli.sh" create)
[[ $(print -r -- "$response" | jq -r '.ok') == true ]]
created=$(print -r -- "$response" | jq -r '.data.path')
[[ -f $created ]]
[[ ${created:h:t} == titre-test ]]
[[ $(print -r -- "$response" | jq -r '.data.status') == created ]]

response=$(print '{"category":"spectacle","title":"Titre de test","slug":"titre-test"}' | ARTICLE_ROOT="$project" "$scripts_dir/article-cli.sh" create)
[[ $(print -r -- "$response" | jq -r '.data.status') == existing ]]

response=$(print '{"category":"film","id":"99","query":"Film de test","slug":"film-raycast-test"}' | \
  HUGO_TMDB=test TMDB_MOVIE_FIXTURE_DIR="$test_dir/fixtures" WIKIDATA_API_BASE_URL='http://127.0.0.1:1' \
  ARTICLE_ROOT="$project" "$scripts_dir/article-cli.sh" create)
[[ $(print -r -- "$response" | jq -r '.data.status') == created ]]
[[ -f "$project/content/film/film-raycast-test/index.md" ]]

response=$(print '{"category":"serie","id":"42","query":"Série de test","slug":"serie-raycast-test","seasons":"all"}' | \
  HUGO_TMDB=test TMDB_FIXTURE_DIR="$test_dir/fixtures" ARTICLE_ROOT="$project" "$scripts_dir/article-cli.sh" create)
[[ $(print -r -- "$response" | jq -r '.data.status') == created ]]
[[ -f "$project/content/serie/serie-raycast-test/index.md" ]]

photo_source="$scripts_dir/../themes/nicolasfurno/static/img/icon-512.png"
response=$(jq -cn --arg file "$photo_source" '{category:"photo",title:"Photo Raycast",slug:"photo-raycast-test",files:[$file],header:"icon-512.png"}' | \
  ARTICLE_ROOT="$project" "$scripts_dir/article-cli.sh" create)
[[ $(print -r -- "$response" | jq -r '.data.status') == created ]]
[[ -f "$project/content/photo/photo-raycast-test/icon-512.png" ]]

if response=$(print '{"category":"spectacle","query":""}' | ARTICLE_ROOT="$project" "$scripts_dir/article-cli.sh" search); then
  print -u2 'Une recherche vide aurait dû échouer.'
  exit 1
fi
[[ $(print -r -- "$response" | jq -r '.ok') == false ]]
[[ $(print -r -- "$response" | jq -r '.error.code') == search_failed ]]

request="$project/request.json"
print '{"id":"42","label":"Sélection attendue"}' > "$request"
selected=$(print '99\tAutre résultat' | ARTICLE_REQUEST_FILE="$request" "$scripts_dir/lib/raycast-fzf.sh" --header 'Quel album ?')
[[ $selected == $'42\tSélection attendue' ]]

print '{"query":"Recherche test","slug":"slug-attendu"}' > "$request"
for header in 'Quel film ?' 'Quel livre ?' 'Quel album ?' 'Quel jeu vidéo ?' 'Quel titre ?'; do
  value=$(ARTICLE_REQUEST_FILE="$request" "$scripts_dir/lib/raycast-gum.sh" input --header "$header" --width 60)
  [[ $value == 'Recherche test' ]]
done
value=$(ARTICLE_REQUEST_FILE="$request" "$scripts_dir/lib/raycast-gum.sh" input --header 'Changer le slug ?' --value 'slug-proposé')
[[ $value == 'slug-attendu' ]]

print 'Tests du protocole CLI réussis.'
