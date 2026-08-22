#!/bin/zsh
set -euo pipefail
script_dir=${0:A:h}
lib_dir=${script_dir:h}/lib
services_dir=${script_dir:h}/services
source "$lib_dir/article.sh"
article_require_tools
query=$("$article_gum_bin" input --header 'Quel album ?' --width 60) || article_cancel
[[ -n $query ]] || article_die 'Le titre est obligatoire.'
search=$(/usr/bin/curl --fail --silent --show-error --get 'https://itunes.apple.com/search' --data-urlencode "term=$query" --data-urlencode country=FR --data-urlencode media=music --data-urlencode entity=album --data-urlencode lang=fr_fr)
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
lookup=$(/usr/bin/curl --fail --silent --show-error "https://itunes.apple.com/lookup?country=FR&lang=fr_fr&id=$id")
meta=$(print -r -- "$lookup" | jq -cS '.results[0]')
name=$(print -r -- "$meta" | jq -er '.collectionName')
artist=$(print -r -- "$meta" | jq -er '.artistName')
title="*$name*, $artist"
country=''
artist_slug=$artist
entity_id=$("$services_dir/wikidata.sh" match "$artist" 2>/dev/null || true)
if [[ -n $entity_id ]]; then
  profile=$("$services_dir/wikidata.sh" profile "$entity_id" 2>/dev/null || true)
  country=$(print -r -- "$profile" | jq -r '.country // empty')
  human=$(print -r -- "$profile" | jq -r '.human // false')
  surname=$(print -r -- "$profile" | jq -r '.surname // empty')
  [[ $human == true && -n $surname ]] && artist_slug=$surname
fi
slug_title="*$name*, $artist_slug"
slug=$(article_slug "$(print -rn -- "$slug_title" | "$lib_dir/slugify.pl" propose)") || article_cancel
file=$(article_create album "$slug" "$title" $'id: '"$id"$'\n')
[[ -n $country ]] && article_set_frontmatter "$file" pays "${(L)country}"
target=${file:h}; print -r -- "$meta" > "$target/meta.json"
art=$(print -r -- "$meta" | jq -r '.artworkUrl100 // empty' | /usr/bin/sed 's/100x100bb/3000x3000bb/')
if [[ -n $art ]]; then
  image="$(print -rn -- "$name" | "$lib_dir/slugify.pl" propose).jpg"
  if ! /usr/bin/curl --fail --silent --show-error --location --remove-on-error "$art" --output "$target/$image"; then
    fallback=$(print -r -- "$meta" | jq -r '.artworkUrl100 // empty')
    /usr/bin/curl --fail --silent --show-error --location --remove-on-error "$fallback" --output "$target/$image" || print -u2 'Avertissement : couverture indisponible.'
  fi
  [[ -f $target/$image ]] && article_set_frontmatter "$file" image "$image"
fi
article_open "$file"
