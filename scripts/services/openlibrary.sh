#!/bin/zsh
set -euo pipefail
script_dir=${0:A:h}
source "$script_dir/../lib/network.sh"

ol_request() {
  local fixture_name=$1 fixture=${OPENLIBRARY_FIXTURE_DIR:-}
  shift
  if [[ -n $fixture && -f "$fixture/$fixture_name" ]]; then
    /bin/cat "$fixture/$fixture_name"
    return
  fi
  network_curl --fail --silent --show-error --retry 2 --retry-all-errors --retry-delay 1 "$@"
}

case ${1:-} in
  search)
    shift
    ol_request openlibrary-search.json --get 'https://openlibrary.org/search.json' \
      --data-urlencode "q=$*" --data-urlencode 'limit=20' \
      --data-urlencode 'fields=key,title,author_name,publisher,first_publish_year,number_of_pages_median,isbn,series' | jq -r '
      .docs[]?
      | select(.key? and .title?)
      | (.key | sub("^/works/"; "")) as $id
      | [.key, .title, ((.author_name // []) | join(", ")),
         ((.publisher // [])[0] // ""), (.first_publish_year // ""),
         (.number_of_pages_median // 0), ((.isbn // [])[0] // "")]
      | [($id | "ol:" + .), .[1], .[2], .[3], (.[4] | tostring)] | @tsv'
    ;;
  record)
    id=${2#ol:}
    query=${3:-$id}
    [[ -n $id ]] || exit 2
    # Le résultat de recherche est la source complète du repli : Open Library
    # identifie durablement l’œuvre (OL…W), pas nécessairement l’édition choisie.
    ol_request openlibrary-search.json --get 'https://openlibrary.org/search.json' \
      --data-urlencode "q=$query" --data-urlencode 'limit=20' \
      --data-urlencode 'fields=key,title,author_name,publisher,first_publish_year,number_of_pages_median,isbn,series' | jq -cS --arg id "$id" '
      .docs[]? | select(.key == "/works/" + $id) | {
        openLibraryId: $id, catalogSource: "openlibrary",
        title, authors: (.author_name // []),
        publisher: ((.publisher // [])[0] // ""),
        publishedDate: ((.first_publish_year // "") | tostring),
        pageCount: (.number_of_pages_median // 0),
        isbn13: ((.isbn // [] | map(select(length == 13)) | .[0]) // ""),
        series: (.series // [])
      } | with_entries(select(.value != "" and .value != 0 and .value != []))'
    ;;
  *) print -u2 'Usage : openlibrary.sh search <requête> | record <ol:OL…W>'; exit 2 ;;
esac
