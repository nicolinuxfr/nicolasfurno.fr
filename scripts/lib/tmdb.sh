#!/bin/zsh

# Fonctions communes aux clients TMDB. Le script appelant doit fournir une
# fonction request CLÉ ENDPOINT PARAMÈTRES… qui renvoie la réponse JSON.

tmdb_library_dir=${${(%):-%N}:A:h}
source "$tmdb_library_dir/people.sh"

tmdb_singular_query() {
  local query=$1
  print -r -- "$query" | /usr/bin/sed -E 's/([[:alpha:]]{3,})s([[:space:]]*)$/\1\2/I'
}

tmdb_merge_search_results() {
  local primary=$1 alternative=$2
  jq -cn \
    --argjson primary "$primary" \
    --argjson alternative "$alternative" '
      ([range(0; ([($primary.results | length), ($alternative.results | length)] | max)) as $index
        | $primary.results[$index], $alternative.results[$index]]
       | map(select(. != null))) as $interleaved
      | reduce $interleaved[] as $result
          ({results: [], seen: {}};
           ($result.id | tostring) as $id
           | if .seen[$id] then .
             else .results += [$result] | .seen[$id] = true
             end)
      | $primary * {results: .results}'
}

tmdb_search_response() {
  local key=$1 endpoint=$2 query=$3
  shift 3

  local response singular_query singular_response
  response=$(request "$key" "$endpoint" "query=$query" "$@") || return

  # TMDB ne rapproche pas toujours un pluriel de son singulier. Le site web
  # est plus tolérant, mais l’API omet par exemple « 10 Dance » pour
  # « 10dances » et « House of the Dragon » pour « dragons ».
  singular_query=$(tmdb_singular_query "$query")
  if [[ "$singular_query" != "$query" ]]; then
    singular_response=$(request "$key" "$endpoint" "query=$singular_query" "$@") || return
    response=$(tmdb_merge_search_results "$response" "$singular_response") || return
  fi

  print -r -- "$response"
}
