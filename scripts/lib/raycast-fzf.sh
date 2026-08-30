#!/bin/zsh
set -euo pipefail

request=${ARTICLE_REQUEST_FILE:?}
input=$(/bin/cat)
header=''
multi=false
while (( $# )); do
  case $1 in
    --header) header=${2:-}; shift 2 ;;
    --multi) multi=true; shift ;;
    *) shift ;;
  esac
done

if $multi || [[ $header == Quelles\ saisons* ]]; then
  seasons=$(jq -r '.seasons // "all"' "$request")
  if [[ $seasons == all ]]; then
    print -r -- "$input" | /usr/bin/awk -F '\t' '$1 == "all" { print; exit }'
  else
    wanted=(${(s:,:)seasons})
    for season in $wanted; do
      print -r -- "$input" | /usr/bin/awk -F '\t' -v value="$season" '$1 == value { print; exit }'
    done
  fi
  exit 0
fi

case $header in
  *image*d’en-tête*) wanted=$(jq -r '.header // ""' "$request") ;;
  *graphie*) wanted=$(jq -r '.displayTitle // ""' "$request") ;;
  *) wanted=$(jq -r '.id // "" | tostring' "$request") ;;
esac

if [[ -n $wanted ]]; then
  selected=$(print -r -- "$input" | /usr/bin/awk -F '\t' -v value="$wanted" '$1 == value || $0 == value { print; exit }')
fi
if [[ -z ${selected:-} && -n $wanted && $header != *graphie* && $header != *image*d’en-tête* ]]; then
  selected="$wanted"$'\t'"$(jq -r '.label // .title // .query // "Sélection"' "$request")"
fi
[[ -n ${selected:-} ]] || selected=$(print -r -- "$input" | /usr/bin/sed -n '1p')
print -r -- "$selected"
