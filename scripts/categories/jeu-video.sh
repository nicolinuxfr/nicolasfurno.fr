#!/bin/zsh
set -euo pipefail
script_dir=${0:A:h}
lib_dir=${script_dir:h}/lib
source "$lib_dir/article.sh"
source "$lib_dir/saga.sh"
article_require_tools
query=$("$article_gum_bin" input --header 'Quel jeu vidéo ?' --width 60) || article_cancel
[[ -n $query ]] || article_die 'Le titre est obligatoire.'
encoded_query=$(print -rn -- "$query" | jq -sRr @uri)
search=$(network_curl --fail --silent --show-error "https://steamcommunity.com/actions/SearchApps/$encoded_query")
rows=$(print -r -- "$search" | jq -r '.[] | [.appid, .name] | @tsv')
[[ -n $rows ]] || article_die "Aucun jeu ne correspond à « $query »."
choice=$(print -r -- "$rows" | article_pick_row 'Quel jeu ?') || exit 0
[[ -n $choice ]] || exit 0
id=${choice%%$'\t'*}
[[ -n $id ]] || exit 0
article_check_existing jeu-video id "$id"
details=$(network_curl --fail --silent --show-error "https://store.steampowered.com/api/appdetails?lang=fr&appids=$id")
success=$(print -r -- "$details" | jq -r --arg id "$id" '.[$id].success')
[[ $success == true ]] || article_die 'Steam ne fournit pas les métadonnées de ce jeu.'
name=$(print -r -- "$details" | jq -er --arg id "$id" '.[$id].data.name')
saga_candidate=$(print -r -- "$details" | jq -r --arg id "$id" '.[$id].data.franchises[0].name // empty')
saga_weight=$(saga_weight_from_text "$name")
if [[ -z $saga_candidate && -n $saga_weight ]]; then
  saga_candidate=$(print -rn -- "$name" | /usr/bin/perl -CS -Mutf8 -pe 's/\s*[-:]?\s*\d+\s*$//')
fi
saga_name=''
if [[ -n $saga_candidate ]]; then
  saga_name=$(saga_existing_by_name "$saga_candidate")
  [[ -n $saga_name ]] || saga_name=$saga_candidate
else
  saga_name=$(saga_existing_by_name "$name")
fi
if [[ -n $saga_candidate || -n $saga_name ]]; then
  saga_meta=$(saga_frontmatter "$saga_name" "$saga_weight" true)
else
  saga_meta=''
fi
slug=$(article_slug "$(print -rn -- "$name" | "$lib_dir/slugify.pl" propose)") || article_cancel
hours=$("$article_gum_bin" input --header 'Temps de jeu en heures (facultatif)' --placeholder 0) || article_cancel
[[ -z $hours || $hours == <-> ]] || article_die 'Le temps doit être un nombre entier.'
extra=$'id: '"$id"$'\n'
[[ -z $saga_meta ]] || extra+="$saga_meta"$'\n'
file=$(article_create jeu-video "$slug" "*$name*" "$extra")
target=${file:h}; print -r -- "$details" | jq -cS --arg id "$id" '.[$id]' > "$target/meta.json"
image="$(print -rn -- "$name" | "$lib_dir/slugify.pl" propose).jpg"
image_path="$target/$image"
image_urls=(
  "https://shared.akamai.steamstatic.com/store_item_assets/steam/apps/$id/library_600x900_2x.jpg"
  "https://cdn.akamai.steamstatic.com/steam/apps/$id/library_600x900_2x.jpg"
)
for image_url in "${image_urls[@]}"; do
  if network_curl --fail --silent --show-error --location --remove-on-error "$image_url" --output "$image_path"; then
    break
  fi
done
[[ -f $image_path ]] || print -u2 'Avertissement : capsule verticale Steam indisponible.'
article_set_frontmatter "$file" temps "${hours:-0}"
article_open "$file"
