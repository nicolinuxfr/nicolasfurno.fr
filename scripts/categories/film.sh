#!/bin/zsh
set -euo pipefail
script_dir=${0:A:h}
lib_dir=${script_dir:h}/lib
services_dir=${script_dir:h}/services
source "$lib_dir/article.sh"
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
file=$(article_create film "$slug" "$title" $'id: '"$id"$'\n')
target=${file:h}
print -r -- "$data" | jq -cS 'del(.credits)' > "$target/meta.json"
print -r -- "$data" | jq -cS '.credits' > "$target/cast.json"
poster=$(print -r -- "$data" | jq -r '.poster_path // empty')
if [[ -n $poster ]]; then
  image="$(print -rn -- "$name" | "$lib_dir/slugify.pl" propose).${poster:e:l}"
  "$services_dir/tmdb-movie.sh" image "$poster" "$target/$image" || print -u2 'Avertissement : affiche TMDB indisponible.'
fi
article_open "$file"
