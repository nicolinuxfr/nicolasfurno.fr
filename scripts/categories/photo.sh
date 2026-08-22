#!/bin/zsh
set -euo pipefail
script_dir=${0:A:h}
lib_dir=${script_dir:h}/lib
source "$lib_dir/article.sh"
article_require_tools

title=$("$article_gum_bin" input --header 'Quel titre ?' --width 80) || article_cancel
[[ -n $title ]] || article_die 'Le titre est obligatoire.'
slug=$(article_slug "$(print -rn -- "$title" | "$lib_dir/slugify.pl" propose)") || article_cancel
files=$(/usr/bin/osascript <<'APPLESCRIPT'
set chosenFiles to choose file with prompt "Choisir les photos à importer" with multiple selections allowed
set output to ""
repeat with chosenFile in chosenFiles
  set output to output & POSIX path of chosenFile & linefeed
end repeat
return output
APPLESCRIPT
) || exit 0
sources=("${(@f)files}")
(( ${#sources} > 0 )) || article_die 'Aucune photo sélectionnée.'
typeset -a names
stage=$(/usr/bin/mktemp -d "${TMPDIR:-/tmp}/nicolasfurno-photo.XXXXXX")
trap '/bin/rm -rf -- "$stage"' EXIT INT TERM
for source in $sources; do
  [[ -f $source ]] || article_die "Photo introuvable : $source"
  extension=${source:e:l}
  [[ $extension == (jpg|jpeg|png) ]] || article_die "Format non pris en charge : $source"
  (( ${names[(Ie)${source:t}]} == 0 )) || article_die "Deux photos portent le même nom : ${source:t}"
  destination="$stage/${source:t}"
  /bin/cp -- "$source" "$destination"
  /usr/bin/sips -Z 2000 "$destination" >/dev/null
  source_meta=$(/usr/bin/sips -g creation -g make -g model -g profile "$source" 2>/dev/null || true)
  converted_meta=$(/usr/bin/sips -g creation -g make -g model -g profile "$destination" 2>/dev/null || true)
  for property in creation make model profile; do
    original=$(print -r -- "$source_meta" | /usr/bin/awk -F ': ' -v key="$property" '$1 ~ key {print $2}')
    converted=$(print -r -- "$converted_meta" | /usr/bin/awk -F ': ' -v key="$property" '$1 ~ key {print $2}')
    [[ -z $original || $original == '<nil>' || $original == "$converted" ]] || article_die "La conversion n’a pas conservé $property pour ${source:t}."
  done
  names+=("${source:t}")
done
header=$(print -rl -- $names | article_pick 'Quelle image d’en-tête ?') || exit 0
[[ -n $header ]] || exit 0
file=$(article_create photo "$slug" "$title")
target=${file:h}
for name in $names; do
  /bin/cp -- "$stage/$name" "$target/$name"
done
article_set_frontmatter "$file" image "$header"
article_open "$file"
