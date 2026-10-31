#!/bin/zsh
set -euo pipefail
script_dir=${0:A:h}
lib_dir=${script_dir:h}/lib
source "$lib_dir/article.sh"
article_require_tools
magick_bin=${commands[magick]:-}
[[ -n $magick_bin ]] || article_die 'ImageMagick (magick) est requis pour convertir les photos en q93 et vérifier leurs métadonnées GPS.'

photo_warn() {
  if [[ -n ${ARTICLE_WARNING_LOG:-} ]]; then
    print -r -- "$1" >> "$ARTICLE_WARNING_LOG"
  else
    print -u2 -- "$1"
  fi
}

title=$("$article_gum_bin" input --header 'Quel titre ?' --width 80) || article_cancel
[[ -n $title ]] || article_die 'Le titre est obligatoire.'
slug=$(article_slug "$(print -rn -- "$title" | "$lib_dir/slugify.pl" propose)") || article_cancel
header_source=""
if [[ -n ${ARTICLE_PHOTO_FILES:-} ]]; then
  files=$ARTICLE_PHOTO_FILES
  if [[ -n ${ARTICLE_REQUEST_FILE:-} && -f $ARTICLE_REQUEST_FILE ]]; then
    header_source=$(jq -r '.header // ""' "$ARTICLE_REQUEST_FILE")
  fi
else
  files=$(/usr/bin/osascript <<'APPLESCRIPT'
set chosenFiles to choose file with prompt "Choisir les photos à importer" with multiple selections allowed
set output to ""
repeat with chosenFile in chosenFiles
  set output to output & POSIX path of chosenFile & linefeed
end repeat
return output
APPLESCRIPT
) || exit 0
fi
sources=("${(@f)files}")
(( ${#sources} > 0 )) || article_die 'Aucune photo sélectionnée.'
typeset -a names
stage=$(/usr/bin/mktemp -d "${TMPDIR:-/tmp}/nicolasfurno-photo.XXXXXX")
trap '/bin/rm -rf -- "$stage"' EXIT INT TERM
for source in $sources; do
  [[ -f $source ]] || article_die "Photo introuvable : $source"
  extension=${source:e:l}
  [[ $extension == (jpg|jpeg|png) ]] || article_die "Format non pris en charge : $source"
  name="${source:t:r}.jpg"
  (( ${names[(Ie)$name]} == 0 )) || article_die "Deux photos produisent le même nom : $name"
  destination="$stage/$name"
  source_meta=$(/usr/bin/sips -g format -g pixelWidth -g pixelHeight -g creation -g make -g model -g profile "$source" 2>/dev/null || true)
  source_quality=''
  target_quality=93
  copy_unchanged=false
  expect_q93=true
  if [[ $extension == (jpg|jpeg) ]]; then
    source_quality=$("$magick_bin" identify -format '%Q' "${source}[0]" 2>/dev/null || true)
    [[ $source_quality == <-> ]] && (( source_quality >= 1 && source_quality <= 100 )) || article_die "Impossible d’estimer la qualité JPEG de ${source:t}."
    dimensions=$("$magick_bin" identify -format '%w %h' "${source}[0]" 2>/dev/null)
    source_width=${dimensions%% *}
    source_height=${dimensions##* }
    if (( source_quality <= 93 )); then
      target_quality=$source_quality
      expect_q93=false
      if (( source_width <= 2000 && source_height <= 2000 )); then
        /bin/cp -- "$source" "$destination"
        copy_unchanged=true
      fi
    fi
  fi
  source_gps=$("$magick_bin" identify -format '%[EXIF:GPSLatitude]|%[EXIF:GPSLongitude]' "${source}[0]" 2>/dev/null || true)
  source_latitude=${source_gps%%|*}
  source_longitude=${source_gps#*|}
  if [[ -z $source_latitude || -z $source_longitude ]]; then
    photo_warn "GPS absent dans ${source:t}. Vérifie que Photos a inclus les informations de lieu."
  fi

  if ! $copy_unchanged; then
    "$magick_bin" "${source}[0]" -auto-orient -resize '2000x2000>' -quality "$target_quality" "$destination"
  fi
  converted_meta=$(/usr/bin/sips -g creation -g make -g model -g profile "$destination" 2>/dev/null || true)
  for property in creation make model; do
    original=$(print -r -- "$source_meta" | /usr/bin/awk -F ': ' -v key="$property" '$1 ~ key {print $2}')
    converted=$(print -r -- "$converted_meta" | /usr/bin/awk -F ': ' -v key="$property" '$1 ~ key {print $2}')
    [[ -z $original || $original == '<nil>' || $original == "$converted" ]] || article_die "La conversion n’a pas conservé $property pour ${source:t}."
  done
  source_icc=$("$magick_bin" identify -format '%[profile:icc]' "${source}[0]" 2>/dev/null | /usr/bin/shasum -a 256 | /usr/bin/awk '{print $1}')
  output_icc=$("$magick_bin" identify -format '%[profile:icc]' "$destination" 2>/dev/null | /usr/bin/shasum -a 256 | /usr/bin/awk '{print $1}')
  [[ $source_icc == "$output_icc" ]] || article_die "La conversion n’a pas conservé le profil ICC de ${source:t}."
  if ! $copy_unchanged; then
    output_quality=$("$magick_bin" identify -format '%Q' "$destination")
    if $expect_q93; then
      [[ $output_quality == 93 ]] || article_die "La conversion de ${source:t} n’a pas produit un JPEG q93."
    else
      (( output_quality <= 93 )) || article_die "La réduction de ${source:t} a dépassé q93."
    fi
  fi
  output_gps=$("$magick_bin" identify -format '%[EXIF:GPSLatitude]|%[EXIF:GPSLongitude]' "$destination" 2>/dev/null || true)
  output_latitude=${output_gps%%|*}
  output_longitude=${output_gps#*|}
  if [[ -n $source_latitude && -n $source_longitude && ( -z $output_latitude || -z $output_longitude ) ]]; then
    article_die "La conversion a perdu les coordonnées GPS de ${source:t}."
  fi
  names+=("$name")
done
if [[ -n $header_source ]]; then
  selected=false
  for source in $sources; do
    [[ $source == $header_source ]] && selected=true
  done
  $selected || article_die 'L’image d’en-tête ne fait pas partie des photos sélectionnées.'
  header="${header_source:t:r}.jpg"
else
  header=$(print -rl -- $names | article_pick 'Quelle image d’en-tête ?') || exit 0
fi
[[ -n $header ]] || exit 0
file=$(article_create photo "$slug" "$title")
target=${file:h}
for name in $names; do
  /bin/cp -- "$stage/$name" "$target/$name"
done
article_set_frontmatter "$file" image "$header"
article_open "$file"
