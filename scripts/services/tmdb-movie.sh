#!/bin/zsh
set -euo pipefail

script_dir=${0:A:h}
repo_root=${script_dir:h:h}
source "$script_dir/../lib/tmdb.sh"
source "$script_dir/../lib/network.sh"
api_base=${TMDB_API_BASE_URL:-https://api.themoviedb.org/3}
image_base=${TMDB_IMAGE_BASE_URL:-https://image.tmdb.org/t/p/original}
fixture_dir=${TMDB_MOVIE_FIXTURE_DIR:-}

die() { print -u2 -- "$*"; exit 1 }
token() {
  local value=${HUGO_TMDB:-} line
  if [[ -z $value && -f $repo_root/.envrc ]]; then
    line=$(/usr/bin/sed -En 's/^[[:space:]]*(export[[:space:]]+)?HUGO_TMDB[[:space:]]*=[[:space:]]*//p' "$repo_root/.envrc" | /usr/bin/tail -1)
    value=${line#\"}; value=${value%\"}; value=${value#\'}; value=${value%\'}
  fi
  [[ -n $value ]] || die 'HUGO_TMDB est absent de l’environnement et de .envrc.'
  print -r -- "$value"
}
request() {
  local key=$1 endpoint=$2; shift 2
  [[ -n $fixture_dir && -f $fixture_dir/$key.json ]] && { /bin/cat "$fixture_dir/$key.json"; return; }
  local value; value=$(token)
  local -a command=(--fail-with-body --silent --show-error --retry 3 --retry-all-errors --get "$api_base/$endpoint" --header 'accept: application/json' --data-urlencode "language=${TMDB_LANGUAGE:-fr-FR}")
  [[ $value == eyJ* ]] && command+=(--header "Authorization: Bearer $value") || command+=(--data-urlencode "api_key=$value")
  local parameter; for parameter in "$@"; do command+=(--data-urlencode "$parameter"); done
  network_curl "${command[@]}"
}
case ${1:-} in
  search)
    query=${2:-}; [[ -n $query ]] || die 'La recherche TMDB est vide.'
    tmdb_search_response search-movie search/movie "$query" 'include_adult=false' | jq -r --arg query "$query" '
      .results
      | (map(select((.title | ascii_downcase) == ($query | ascii_downcase)))
         + map(select((.title | ascii_downcase) != ($query | ascii_downcase))))[]
      | (.release_date // "")[:4] as $year
      | [.id, (.title + (if $year == "" then "" else " (" + $year + ")" end))]
      | @tsv'
    ;;
  movie)
    id=${2:-}; [[ $id == <-> ]] || die 'Identifiant TMDB invalide.'
    localized=$(request "movie-$id" "movie/$id" 'append_to_response=credits')
    western=$(TMDB_LANGUAGE=en-US request "movie-$id" "movie/$id" 'append_to_response=credits')
    people_westernize_tmdb "$localized" "$western" | jq -cS .
    ;;
  collection)
    id=${2:-}; [[ $id == <-> ]] || die 'Identifiant de collection TMDB invalide.'
    request "collection-$id" "collection/$id" | jq -cS .
    ;;
  person-profile)
    id=${2:-}; [[ $id == <-> ]] || die 'Identifiant TMDB invalide.'
    request "person-$id" "person/$id" 'append_to_response=external_ids' | jq -c '
      {
        wikidata_id: (.external_ids.wikidata_id // ""),
        western_name: (
          [.also_known_as[]?, .name]
          | map(select(
              test("\\p{Latin}")
              and (test("[\\p{Han}\\p{Hiragana}\\p{Katakana}\\p{Cyrillic}\\p{Arabic}]") | not)
            ))
          | .[0] // ""
        )
      }'
    ;;
  image)
    path=${2:-}; destination=${3:-}; [[ -n $path && -n $destination ]] || die "Usage: ${0:t} image CHEMIN SORTIE"
    if [[ -n $fixture_dir ]]; then /bin/cp "$fixture_dir/image-${path:t}" "$destination"
    else network_curl --fail --silent --show-error --retry 3 --retry-all-errors --remove-on-error "$image_base/${path#/}" --output "$destination"; fi
    ;;
  *) die "Usage: ${0:t} search REQUÊTE | movie ID | collection ID | person-profile ID | image CHEMIN SORTIE" ;;
esac
