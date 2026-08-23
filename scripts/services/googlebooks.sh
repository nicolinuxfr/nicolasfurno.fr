#!/bin/zsh
set -euo pipefail
script_dir=${0:A:h}
source "$script_dir/../lib/network.sh"

google_request() {
  local fixture=${GOOGLEBOOKS_FIXTURE_DIR:-} key=${HUGO_GOOGLE_BOOKS:-}
  if [[ -n $fixture && -f "$fixture/googlebooks.json" ]]; then
    /bin/cat "$fixture/googlebooks.json"
    return
  fi
  network_curl --fail --silent --show-error --retry 2 --retry-all-errors --retry-delay 1 \
    --get 'https://www.googleapis.com/books/v1/volumes' \
    --data-urlencode "q=$1" --data-urlencode maxResults=20 ${key:+--data-urlencode "key=$key"}
}

google_record_request() {
  local id=$1 fixture=${GOOGLEBOOKS_FIXTURE_DIR:-} key=${HUGO_GOOGLE_BOOKS:-}
  if [[ -n $fixture && -f "$fixture/googlebooks-record.json" ]]; then
    /bin/cat "$fixture/googlebooks-record.json"
    return
  fi
  network_curl --fail --silent --show-error --retry 2 --retry-all-errors --retry-delay 1 \
    "https://www.googleapis.com/books/v1/volumes/$id" ${key:+--get --data-urlencode "key=$key"}
}

case ${1:-} in
  search)
    shift
    google_request "intitle:$*" | jq -r '.items[]? | [.id, .volumeInfo.title, ((.volumeInfo.authors // []) | join(", ")), (.volumeInfo.publisher // ""), (.volumeInfo.publishedDate // "")] | @tsv'
    ;;
  record)
    [[ -n ${2:-} ]] || exit 2
    google_record_request "$2" | jq -cS --arg id "$2" '.volumeInfo | {googleBooksId: $id, catalogSource: "googlebooks", title, authors: (.authors // []), publisher: (.publisher // ""), publishedDate: ((.publishedDate // "") | capture("(?<year>(19|20)[0-9]{2})")? | .year // ""), pageCount: (.pageCount // 0), isbn13: ((.industryIdentifiers // [] | map(select(.type == "ISBN_13") | .identifier) | .[0]) // "")} | with_entries(select(.value != "" and .value != 0 and .value != []))'
    ;;
  *) print -u2 'Usage : googlebooks.sh search <requête> | record <id>'; exit 2 ;;
esac
