#!/bin/zsh

set -euo pipefail

test_dir=${0:A:h}
scripts_dir=${test_dir:h}
fixtures="$test_dir/fixtures"
temporary=$(/usr/bin/mktemp -d "${TMPDIR:-/tmp}/nicolasfurno-services-test.XXXXXX")
trap '/bin/rm -rf -- "$temporary"' EXIT INT TERM
/bin/mkdir -p "$temporary/google" "$temporary/wikidata"
print -r -- '{"items":[{"id":"book-1","volumeInfo":{"title":"Livre test","authors":["Auteur Test"],"publisher":"Maison Test","publishedDate":"2025"}}]}' > "$temporary/google/googlebooks.json"
print -r -- '{"volumeInfo":{"title":"Livre test","authors":["Auteur Test"],"publisher":"Maison Test","publishedDate":"2025-04-01","pageCount":240,"industryIdentifiers":[{"type":"ISBN_13","identifier":"9780000000000"}]}}' > "$temporary/google/googlebooks-record.json"
print -r -- '{"search":[{"id":"Q999","label":"Nom approchant"},{"id":"Q100","label":"Personne Test"}]}' > "$temporary/wikidata/search.json"
print -r -- '{"entities":{"Q100":{"claims":{"P27":[{"mainsnak":{"datavalue":{"value":{"id":"Q200"}}}}],"P31":[{"mainsnak":{"datavalue":{"value":{"id":"Q5"}}}}],"P734":[{"mainsnak":{"datavalue":{"value":{"id":"Q300"}}}}]}}}}' > "$temporary/wikidata/entity-Q100.json"
print -r -- '{"entities":{"Q200":{"claims":{"P297":[{"mainsnak":{"datavalue":{"value":"FR"}}}]}},"Q300":{"labels":{"fr":{"value":"Test"}}}}}' > "$temporary/wikidata/related.json"
export BNF_FIXTURE_DIR=$fixtures
export OPENLIBRARY_FIXTURE_DIR=$fixtures
export TMDB_MOVIE_FIXTURE_DIR=$fixtures
export TMDB_FIXTURE_DIR=$fixtures
export GOOGLEBOOKS_FIXTURE_DIR="$temporary/google"
export WIKIDATA_FIXTURE_DIR="$temporary/wikidata"
export HUGO_TMDB=test

# Les assertions portent sur le contrat normalisé de chaque service : nombre de
# colonnes, types, identifiants et champs requis. Le contenu éditorial des
# fixtures n’est volontairement pas testé.
bnf_rows=$("$scripts_dir/services/bnf.sh" search test)
print -r -- "$bnf_rows" | /usr/bin/awk -F '\t' 'NF != 6 { exit 1 }'
bnf_meta=$("$scripts_dir/services/bnf.sh" record fixture)
print -r -- "$bnf_meta" | jq -e '
  (.bnfId | test("^cb[0-9a-z]+$"))
  and (.bnfArk | startswith("ark:/"))
  and (.title | length > 0)
  and (.authors | type == "array" and length > 0)
  and (.publishedDate | test("^(19|20)[0-9]{2}$"))
  and (.pageCount | type == "number" and . > 0)
  and (.isbn13 | test("^[0-9]{13}$"))' >/dev/null

ol_rows=$("$scripts_dir/services/openlibrary.sh" search test)
print -r -- "$ol_rows" | /usr/bin/awk -F '\t' 'NF != 5 || $1 !~ /^ol:OL[0-9]+W$/ { exit 1 }'
ol_id=${${ol_rows%%$'\t'*}#ol:}
ol_meta=$("$scripts_dir/services/openlibrary.sh" record "ol:$ol_id" test)
print -r -- "$ol_meta" | jq -e --arg id "$ol_id" '
  .catalogSource == "openlibrary"
  and .openLibraryId == $id
  and (.title | length > 0)
  and (.authors | type == "array" and length > 0)
  and (.isbn13 | test("^[0-9]{13}$"))' >/dev/null

google_rows=$("$scripts_dir/services/googlebooks.sh" search test)
print -r -- "$google_rows" | /usr/bin/awk -F '\t' 'NF != 5 || $1 == "" { exit 1 }'
google_id=${google_rows%%$'\t'*}
google_meta=$("$scripts_dir/services/googlebooks.sh" record "$google_id")
print -r -- "$google_meta" | jq -e --arg id "$google_id" '
  .catalogSource == "googlebooks"
  and .googleBooksId == $id
  and (.authors | type == "array" and length > 0)
  and (.publishedDate | test("^(19|20)[0-9]{2}$"))
  and (.pageCount | type == "number" and . > 0)
  and (.isbn13 | test("^[0-9]{13}$"))' >/dev/null

[[ $("$scripts_dir/services/wikidata.sh" match 'Personne Test') == Q100 ]]
[[ -z $("$scripts_dir/services/wikidata.sh" match 'Personne absente') ]]
print -r -- '{"search":[{"id":"Q100","label":"Homonyme"},{"id":"Q101","label":"Homonyme"}]}' > "$temporary/wikidata/search.json"
[[ -z $("$scripts_dir/services/wikidata.sh" match Homonyme) ]]
print -r -- '{"search":[{"id":"Q999","label":"Nom approchant"},{"id":"Q100","label":"Personne Test"}]}' > "$temporary/wikidata/search.json"
profile=$("$scripts_dir/services/wikidata.sh" profile Q100)
print -r -- "$profile" | jq -e '
  .country == "fr" and .human == true and .surname == "Test"' >/dev/null

movie_rows=$("$scripts_dir/services/tmdb-movie.sh" search test)
print -r -- "$movie_rows" | /usr/bin/awk -F '\t' 'NF != 2 || $1 !~ /^[0-9]+$/ { exit 1 }'
movie_id=${movie_rows%%$'\t'*}
movie=$("$scripts_dir/services/tmdb-movie.sh" movie "$movie_id")
print -r -- "$movie" | jq -e --argjson id "$movie_id" '
  .id == $id and (.title | length > 0) and (.credits.crew | type == "array")' >/dev/null

tv_rows=$("$scripts_dir/services/tmdb-tv.sh" search test)
print -r -- "$tv_rows" | /usr/bin/awk -F '\t' 'NF != 2 || $1 !~ /^[0-9]+$/ { exit 1 }'
tv_id=${tv_rows%%$'\t'*}
series=$("$scripts_dir/services/tmdb-tv.sh" series "$tv_id")
print -r -- "$series" | jq -e --argjson id "$tv_id" '
  .id == $id and (.name | length > 0) and (.seasons | type == "array" and length > 0)' >/dev/null
selection=$(print -r -- $'1\tPremière\n2\tDeuxième' | "$scripts_dir/services/tmdb-tv.sh" normalize-seasons)
[[ $selection == '1-2' ]]
if print -r -- $'1\tPremière\n3\tTroisième' | "$scripts_dir/services/tmdb-tv.sh" normalize-seasons >/dev/null 2>&1; then
  print -u2 'Une sélection non contiguë aurait dû être refusée.'
  exit 1
fi

print 'Tests des services réussis.'
