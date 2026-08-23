#!/bin/zsh
set -euo pipefail
script_dir=${0:A:h}
lib_dir=${script_dir:h}/lib
services_dir=${script_dir:h}/services
source "$lib_dir/article.sh"
article_require_tools
query=$("$article_gum_bin" input --header 'Quel album ?' --width 60) || article_cancel
[[ -n $query ]] || article_die 'Le titre est obligatoire.'
search=$(network_curl --fail --silent --show-error --get 'https://itunes.apple.com/search' --data-urlencode "term=$query" --data-urlencode country=FR --data-urlencode media=music --data-urlencode entity=album --data-urlencode lang=fr_fr)
rows=$(print -r -- "$search" | jq -r '
  .results[]
  | (.releaseDate // "")[:4] as $year
  | [.collectionId, (.collectionName + " — " + .artistName + (if $year == "" then "" else " (" + $year + ")" end))]
  | @tsv')
[[ -n $rows ]] || article_die "Aucun album ne correspond à « $query »."
choice=$(print -r -- "$rows" | article_pick_row 'Quel album ?') || exit 0
[[ -n $choice ]] || exit 0
id=${choice%%$'\t'*}
[[ -n $id ]] || exit 0
article_check_existing album id "$id"
lookup=$(network_curl --fail --silent --show-error "https://itunes.apple.com/lookup?country=FR&lang=fr_fr&id=$id")
meta=$(print -r -- "$lookup" | jq -cS '.results[0]')
name=$(print -r -- "$meta" | jq -er '.collectionName')
artist=$(print -r -- "$meta" | jq -er '.artistName')
country=''
artists=("${(@f)$(people_split_credits "$artist")}")
artist_names=()
artist_slugs=()
for artist_name in "${artists[@]}"; do
  display_name=$artist_name
  artist_slug=$artist_name
  human=false
  entity_id=$("$services_dir/wikidata.sh" match "$artist_name" 2>/dev/null || true)
  if [[ -n $entity_id ]]; then
    profile=$("$services_dir/wikidata.sh" profile "$entity_id" 2>/dev/null || true)
    [[ -z $country ]] && country=$(print -r -- "$profile" | jq -r '.country // empty')
    human=$(print -r -- "$profile" | jq -r '.human // false')
    wikidata_name=$(print -r -- "$profile" | jq -r '.name // empty')
    surname=$(print -r -- "$profile" | jq -r '.surname // empty')
    display_name=${wikidata_name:-$display_name}
    [[ $human == true && -n $surname ]] && artist_slug=$surname
  fi
  [[ $human == true || ${#artists} -gt 1 ]] && display_name=$(people_name "$display_name")
  artist_names+=("$display_name")
  artist_slugs+=("$artist_slug")
done
artist_title=$(people_join "${artist_names[@]}")
title="*$name*, $artist_title"
artist_slug=$(article_join "${artist_slugs[@]}")
slug_title="*$name*, $artist_slug"
slug=$(article_slug "$(print -rn -- "$slug_title" | "$lib_dir/slugify.pl" propose)") || article_cancel
file=$(article_create album "$slug" "$title" $'id: '"$id"$'\n')
[[ -n $country ]] && article_set_frontmatter "$file" pays "${(L)country}"
target=${file:h}; print -r -- "$meta" > "$target/meta.json"
art=$(print -r -- "$meta" | jq -r '.artworkUrl100 // empty' | /usr/bin/sed 's/100x100bb/3000x3000bb/')
if [[ -n $art ]]; then
  image="$(print -rn -- "$name" | "$lib_dir/slugify.pl" propose).jpg"
  if ! network_curl --fail --silent --show-error --location --remove-on-error "$art" --output "$target/$image"; then
    fallback=$(print -r -- "$meta" | jq -r '.artworkUrl100 // empty')
    network_curl --fail --silent --show-error --location --remove-on-error "$fallback" --output "$target/$image" || print -u2 'Avertissement : couverture indisponible.'
  fi
fi
article_open "$file"
