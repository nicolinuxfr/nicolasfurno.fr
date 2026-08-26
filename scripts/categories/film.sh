#!/bin/zsh
set -euo pipefail
script_dir=${0:A:h}
lib_dir=${script_dir:h}/lib
services_dir=${script_dir:h}/services
source "$lib_dir/article.sh"
source "$lib_dir/saga.sh"
article_require_tools
query=$("$article_gum_bin" input --header 'Quel film ?' --width 60) || article_cancel
[[ -n $query ]] || article_die 'Le titre est obligatoire.'
results=$("$services_dir/tmdb-movie.sh" search "$query")
[[ -n $results ]] || article_die "Aucun film TMDB ne correspond à « $query »."
choice=$(print -r -- "$results" | article_pick_row 'Quel film ?') || exit 0
[[ -n $choice ]] || exit 0
id=${choice%%$'\t'*}
[[ -n $id ]] || exit 0
article_check_existing film id "$id"
data=$("$services_dir/tmdb-movie.sh" movie "$id")
name=$(print -r -- "$data" | jq -er '.title')
collection_id=$(print -r -- "$data" | jq -r '.belongs_to_collection.id // empty')
saga_meta=''
if [[ -n $collection_id ]]; then
  collection=$("$services_dir/tmdb-movie.sh" collection "$collection_id" 2>/dev/null || true)
  collection_name=$(print -r -- "$collection" | jq -r '.name // empty' 2>/dev/null || true)
  [[ -n $collection_name ]] || collection_name=$(print -r -- "$data" | jq -r '.belongs_to_collection.name // empty')
  saga_name=$(saga_existing_by_tmdb_collection "$collection_id")
  [[ -n $saga_name ]] || saga_name=$(saga_existing_by_name "$collection_name" true)
  [[ -n $saga_name ]] || saga_name=$(print -rn -- "$collection_name" | /usr/bin/perl -CS -Mutf8 -pe 's/\s*[-:]?\s*(?:saga|collection)\s*$//i')
  saga_weight=$(print -r -- "$collection" | jq -r --argjson id "$id" '.parts // [] | to_entries[] | select(.value.id == $id) | .key + 1' 2>/dev/null || true)
  saga_meta=$(saga_frontmatter "$saga_name" "$saga_weight" true)
fi
director_names=()
director_slugs=()
while IFS=$'\t' read -r director_id director_name; do
  [[ -n $director_name ]] || continue
  person_profile=$("$services_dir/tmdb-movie.sh" person-profile "$director_id" 2>/dev/null || true)
  wikidata_id=$(print -r -- "$person_profile" | jq -r '.wikidata_id // empty')
  western_name=$(print -r -- "$person_profile" | jq -r '.western_name // empty')
  surname=''
  if [[ -n $wikidata_id ]]; then
    profile=$("$services_dir/wikidata.sh" profile "$wikidata_id" 2>/dev/null || true)
    wikidata_name=$(print -r -- "$profile" | jq -r '.name // empty')
    western_name=${wikidata_name:-$western_name}
    surname=$(print -r -- "$profile" | jq -r '.surname // empty')
  fi
  director_names+=("${western_name:-$director_name}")
  # Certains profils TMDB n’ont pas d’identifiant Wikidata. Dans ce cas,
  # conservons tout de même le nom de famille, plutôt que le nom complet.
  director_slugs+=("${surname:-$(article_surnames "${western_name:-$director_name}")}")
done < <(print -r -- "$data" | jq -r '.credits.crew[] | select(.job == "Director") | [.id, .name] | @tsv')
directors=$(people_join_names "${director_names[@]}")
title="*$name*${directors:+, $directors}"
director_slugs=$(article_join "${director_slugs[@]}")
slug_title="*$name*${director_slugs:+, $director_slugs}"
slug=$(article_slug "$(print -rn -- "$slug_title" | "$lib_dir/slugify.pl" propose)") || article_cancel
extra=$'id: '"$id"$'\n'
[[ -z $saga_meta ]] || extra+="$saga_meta"$'\n'
file=$(article_create film "$slug" "$title" "$extra")
target=${file:h}
print -r -- "$data" | jq -cS 'del(.credits)' > "$target/meta.json"
print -r -- "$data" | jq -cS '.credits' > "$target/cast.json"
poster=$(print -r -- "$data" | jq -r '.poster_path // empty')
if [[ -n $poster ]]; then
  image="$(print -rn -- "$name" | "$lib_dir/slugify.pl" propose).${poster:e:l}"
  "$services_dir/tmdb-movie.sh" image "$poster" "$target/$image" || print -u2 'Avertissement : affiche TMDB indisponible.'
fi
article_open "$file"
