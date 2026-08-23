#!/bin/zsh
set -euo pipefail
script_dir=${0:A:h}
lib_dir=${script_dir:h}/lib
source "$lib_dir/article.sh"
article_require_tools
query=$("$article_gum_bin" input --header 'Quel jeu vidéo ?' --width 60) || article_cancel
[[ -n $query ]] || article_die 'Le titre est obligatoire.'
encoded_query=$(print -rn -- "$query" | jq -sRr @uri)
search=$(/usr/bin/curl --fail --silent --show-error "https://steamcommunity.com/actions/SearchApps/$encoded_query")
rows=$(print -r -- "$search" | jq -r '.[] | [.appid, .name] | @tsv')
[[ -n $rows ]] || article_die "Aucun jeu ne correspond à « $query »."
choice=$(print -r -- "$rows" | article_pick_row 'Quel jeu ?') || exit 0
[[ -n $choice ]] || exit 0
id=${choice%%$'\t'*}
[[ -n $id ]] || exit 0
article_check_existing jeu-video id "$id"
details=$(/usr/bin/curl --fail --silent --show-error "https://store.steampowered.com/api/appdetails?lang=fr&appids=$id")
success=$(print -r -- "$details" | jq -r --arg id "$id" '.[$id].success')
[[ $success == true ]] || article_die 'Steam ne fournit pas les métadonnées de ce jeu.'
name=$(print -r -- "$details" | jq -er --arg id "$id" '.[$id].data.name')
slug=$(article_slug "$(print -rn -- "$name" | "$lib_dir/slugify.pl" propose)") || article_cancel
hours=$("$article_gum_bin" input --header 'Temps de jeu en heures (facultatif)' --placeholder 0) || article_cancel
[[ -z $hours || $hours == <-> ]] || article_die 'Le temps doit être un nombre entier.'
file=$(article_create jeu-video "$slug" "*$name*" $'id: '"$id"$'\n')
target=${file:h}; print -r -- "$details" | jq -cS --arg id "$id" '.[$id]' > "$target/meta.json"
image="$(print -rn -- "$name" | "$lib_dir/slugify.pl" propose).jpg"
image_path="$target/$image"
image_urls=(
  "https://shared.akamai.steamstatic.com/store_item_assets/steam/apps/$id/library_600x900_2x.jpg"
  "https://cdn.akamai.steamstatic.com/steam/apps/$id/library_600x900_2x.jpg"
)
for image_url in "${image_urls[@]}"; do
  if /usr/bin/curl --fail --silent --show-error --location --remove-on-error "$image_url" --output "$image_path"; then
    break
  fi
done
[[ -f $image_path ]] || print -u2 'Avertissement : capsule verticale Steam indisponible.'
article_set_frontmatter "$file" temps "${hours:-0}"
article_open "$file"
