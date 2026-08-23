#!/bin/zsh
set -euo pipefail
script_dir=${0:A:h}
source "$script_dir/../lib/network.sh"

# Client minimal pour les recherches et propriétés Wikidata utilisées par les
# générateurs (personnes, groupes, pays et noms de famille).
command=${1:-}
base=${WIKIDATA_API_BASE_URL:-https://www.wikidata.org/w/api.php}
fixture_dir=${WIKIDATA_FIXTURE_DIR:-}

entity_profile() {
  if [[ -n $fixture_dir && -f "$fixture_dir/entity-$1.json" ]]; then
    /bin/cat "$fixture_dir/entity-$1.json"
    return
  fi
  network_curl --fail --silent --show-error --get "$base" \
    --data-urlencode action=wbgetentities --data-urlencode format=json \
    --data-urlencode props='claims|labels' --data-urlencode languages='fr|en|mul' \
    --data-urlencode "ids=$1"
}

entity_labels_and_claims() {
  if [[ -n $fixture_dir && -f "$fixture_dir/related.json" ]]; then
    /bin/cat "$fixture_dir/related.json"
    return
  fi
  network_curl --fail --silent --show-error --get "$base" \
    --data-urlencode action=wbgetentities --data-urlencode format=json \
    --data-urlencode props='claims|labels' --data-urlencode languages='fr|en' \
    --data-urlencode "ids=$1"
}

case $command in
  match)
    query=${2:-}; [[ -n $query ]] || exit 0
    if [[ -n $fixture_dir && -f "$fixture_dir/search.json" ]]; then
      response=$(/bin/cat "$fixture_dir/search.json")
    else
      response=$(network_curl --fail --silent --show-error --get "$base" \
        --data-urlencode action=wbsearchentities --data-urlencode format=json \
        --data-urlencode language=fr --data-urlencode limit=8 --data-urlencode "search=$query")
    fi
    print -r -- "$response" | jq -r --arg query "$query" \
      '[.search[] | select((.label | ascii_downcase) == ($query | ascii_downcase)) | .id]
       | if length == 1 then .[0] else empty end'
    ;;
  profile)
    id=${2:-}; [[ $id == Q<-> ]] || exit 0
    entity=$(entity_profile "$id")
    country_id=$(print -r -- "$entity" | jq -r '.entities[] | (.claims.P27 // .claims.P495 // []) | .[0].mainsnak.datavalue.value.id // empty')
    surname_id=$(print -r -- "$entity" | jq -r '.entities[] | .claims.P734[0].mainsnak.datavalue.value.id // empty')
    related_ids=$(print -rl -- "$country_id" "$surname_id" | /usr/bin/awk 'NF { printf "%s%s", separator, $0; separator = "|" } END { print "" }')
    related='{"entities":{}}'
    [[ -n $related_ids ]] && related=$(entity_labels_and_claims "$related_ids")
    result=$(print -r -- "$entity" "$related" | jq -sc --arg country "$country_id" --arg surname "$surname_id" '
      .[0] as $entity | .[1] as $related |
      {
        name: ([ $entity.entities[] | (.labels.fr.value // .labels.en.value // .labels.mul.value // "") ][0]),
        country: (if $country == "" then "" else ($related.entities[$country].claims.P297[0].mainsnak.datavalue.value // "" | ascii_downcase) end),
        human: ([ $entity.entities[] | .claims.P31[]?.mainsnak.datavalue.value.id ] | index("Q5") != null),
        surname: (if $surname == "" then "" else ($related.entities[$surname].labels.fr.value // $related.entities[$surname].labels.en.value // "") end)
      }')
    print -r -- "$result"
    ;;
  *) print -u2 'Usage : wikidata.sh match NOM | profile QID'; exit 64 ;;
esac
