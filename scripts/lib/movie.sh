#!/bin/zsh

# Construit le titre éditorial et sa variante destinée au slug à partir des
# crédits TMDB. Les services et bibliothèques sont injectés pour rester testable.
movie_authorship() {
  local data=$1 services_dir=$2 lib_dir=$3 requested_name=${4:-}
  local director_id director_name person_profile wikidata_id western_name
  local profile wikidata_name surname name directors director_slugs title slug_title
  local -a director_names director_slug_values

  name=${requested_name:-$(print -r -- "$data" | jq -er '.title')} || return
  while IFS=$'\t' read -r director_id director_name; do
    [[ -n $director_name ]] || continue
    person_profile=$("$services_dir/tmdb-movie.sh" person-profile "$director_id" 2>/dev/null || true)
    wikidata_id=$(print -r -- "$person_profile" | jq -r '.wikidata_id // empty' 2>/dev/null || true)
    western_name=$(print -r -- "$person_profile" | jq -r '.western_name // empty' 2>/dev/null || true)
    surname=''
    if [[ -n $wikidata_id ]]; then
      profile=$("$services_dir/wikidata.sh" profile "$wikidata_id" 2>/dev/null || true)
      wikidata_name=$(print -r -- "$profile" | jq -r '.name // empty' 2>/dev/null || true)
      western_name=${wikidata_name:-$western_name}
      surname=$(print -r -- "$profile" | jq -r '.surname // empty' 2>/dev/null || true)
    fi
    director_names+=("${western_name:-$director_name}")
    director_slug_values+=("${surname:-$(article_surnames "${western_name:-$director_name}")}")
  done < <(print -r -- "$data" | jq -r '.credits.crew[]? | select(.job == "Director") | [.id, .name] | @tsv')

  directors=$(people_join_names "${director_names[@]}")
  director_slugs=$(article_join "${director_slug_values[@]}")
  title="*$name*${directors:+, $directors}"
  slug_title="*$name*${director_slugs:+, $director_slugs}"
  jq -cn --arg title "$title" --arg slugTitle "$slug_title" --arg directors "$directors" \
    '{title:$title,slugTitle:$slugTitle,directors:$directors}'
}
