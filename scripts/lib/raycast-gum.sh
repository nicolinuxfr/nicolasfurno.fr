#!/bin/zsh
set -euo pipefail

request=${ARTICLE_REQUEST_FILE:?}
command=${1:-}
shift || true

value_arg() {
  local flag=$1 index
  shift
  for (( index = 1; index <= $#; index++ )); do
    if [[ ${@[index]} == $flag ]]; then
      print -r -- "${@[index + 1]:-}"
      return
    fi
  done
}

case $command in
  input)
    header=$(value_arg --header "$@")
    case $header in
      'Quel film ?'|'Quel livre ?'|'Quel album ?'|'Quel jeu vidéo ?'|'Quel titre ?')
        value=$(jq -r '.query // .title // ""' "$request")
        ;;
      'Changer le slug ?')
        value=$(jq -r '.slug // ""' "$request")
        [[ -n $value ]] || value=$(value_arg --value "$@")
        ;;
      'Temps de jeu en heures (facultatif)') value=$(jq -r '.hours // ""' "$request") ;;
      *) value=$(value_arg --value "$@");;
    esac
    print -r -- "$value"
    ;;
  confirm)
    prompt=${@: -1}
    case $prompt in
      *'recherche d’images'*) jq -e '.openImageSearch == true' "$request" >/dev/null ;;
      *) return 1 ;;
    esac
    ;;
  style) print -r -- "${@: -1}" ;;
  *) print -u2 -- "Commande gum non prise en charge : $command"; exit 64 ;;
esac
