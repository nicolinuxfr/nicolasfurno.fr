#!/bin/zsh

set -euo pipefail

script_dir=${0:A:h}
repo_root=${script_dir:h:h}
source "$script_dir/../lib/tmdb.sh"
api_base=${TMDB_API_BASE_URL:-https://api.themoviedb.org/3}
image_base=${TMDB_IMAGE_BASE_URL:-https://image.tmdb.org/t/p/original}
fixture_dir=${TMDB_FIXTURE_DIR:-}

die() {
  print -u2 -- "$*"
  exit 1
}

read_token() {
  local token=${HUGO_TMDB:-}
  local line
  if [[ -z "$token" && -f "$repo_root/.envrc" ]]; then
    line=$(/usr/bin/sed -En 's/^[[:space:]]*(export[[:space:]]+)?HUGO_TMDB[[:space:]]*=[[:space:]]*//p' "$repo_root/.envrc" | /usr/bin/tail -n 1)
    token=${line#\"}
    token=${token%\"}
    token=${token#\'}
    token=${token%\'}
  fi
  [[ -n "$token" ]] || die "HUGO_TMDB est absent de l’environnement et de $repo_root/.envrc."
  print -r -- "$token"
}

fixture_path() {
  local key=$1
  [[ -n "$fixture_dir" ]] || return 1
  print -r -- "$fixture_dir/$key.json"
}

run_curl() {
  local error_file output exit_code
  error_file=$(/usr/bin/mktemp "${TMPDIR:-/tmp}/nicolasfurno-curl.XXXXXX")

  if output=$("$@" 2>"$error_file"); then
    exit_code=0
  else
    exit_code=$?
    /bin/cat "$error_file" >&2
  fi
  /bin/rm -f -- "$error_file"

  (( exit_code == 0 )) || return "$exit_code"
  print -rn -- "$output"
}

request() {
  local key=$1
  local endpoint=$2
  shift 2
  local fixture
  if fixture=$(fixture_path "$key") && [[ -f "$fixture" ]]; then
    /bin/cat "$fixture"
    return
  fi

  local token
  token=$(read_token)
  local -a command
  command=(/usr/bin/curl --fail-with-body --silent --show-error --retry 3 --retry-all-errors
    --get "$api_base/$endpoint"
    --header 'accept: application/json'
    --data-urlencode "language=${TMDB_LANGUAGE:-fr-FR}")
  if [[ "$token" == eyJ* ]]; then
    command+=(--header "Authorization: Bearer $token")
  else
    command+=(--data-urlencode "api_key=$token")
  fi
  local parameter
  for parameter in "$@"; do
    command+=(--data-urlencode "$parameter")
  done
  run_curl "${command[@]}"
}

canonical_json() {
  jq --compact-output --sort-keys .
}

validate_id() {
  [[ $1 == <-> ]] || die "Identifiant TMDB invalide : $1"
}

command=${1:-}
shift || true

case "$command" in
  search)
    query=${1:-}
    [[ -n "$query" ]] || die "La recherche TMDB est vide."
    response=$(tmdb_search_response search search/tv "$query" 'include_adult=false' 'page=1')

    count=$(print -r -- "$response" | jq '.results | length')
    if (( count == 0 )); then
      print -u2 -- "Aucune série TMDB ne correspond à « $query »."
      exit 3
    fi
    print -r -- "$response" | jq -r --arg query "$query" '
      .results
      | (map(select((.name | ascii_downcase) == ($query | ascii_downcase)))
         + map(select((.name | ascii_downcase) != ($query | ascii_downcase))))[]
      | (.first_air_date // "")[:4] as $year
      | [.id, (.name + (if $year == "" then "" else " (" + $year + ")" end))]
      | @tsv'
    ;;

  series)
    id=${1:-}
    validate_id "$id"
    localized=$(request "series-$id" "tv/$id")
    western=$(TMDB_LANGUAGE=en-US request "series-$id" "tv/$id")
    people_westernize_tmdb "$localized" "$western" | canonical_json
    ;;

  season-options)
    id=${1:-}
    validate_id "$id"
    request "series-$id" "tv/$id" | jq -r '
      .seasons
      | map(select(.season_number > 0 and .episode_count > 0))
      | sort_by(.season_number)[]
      | [
          .season_number,
          (.name + " — " + ((.air_date // "")[:4] | if . == "" then "année inconnue" else . end)
           + " — " + (.episode_count | tostring) + " épisodes")
        ]
      | @tsv'
    ;;

  season)
    id=${1:-}
    number=${2:-}
    validate_id "$id"
    [[ $number == <-> && $number -gt 0 ]] || die "Numéro de saison invalide : $number"
    localized=$(request "season-$id-$number" "tv/$id/season/$number" 'append_to_response=aggregate_credits')
    western=$(TMDB_LANGUAGE=en-US request "season-$id-$number" "tv/$id/season/$number" 'append_to_response=aggregate_credits')
    people_westernize_tmdb "$localized" "$western" \
      | jq -e --argjson expected "$number" '
          select(.season_number == $expected)
          | select(.episodes | type == "array")
          | select(.aggregate_credits.cast | type == "array")' \
      | canonical_json
    ;;

  aggregate-credits)
    id=${1:-}
    validate_id "$id"
    localized=$(request "aggregate-$id" "tv/$id/aggregate_credits")
    western=$(TMDB_LANGUAGE=en-US request "aggregate-$id" "tv/$id/aggregate_credits")
    people_westernize_tmdb "$localized" "$western" \
      | jq -e 'select(.cast | type == "array")' \
      | canonical_json
    ;;

  normalize-seasons)
    selection=$(/bin/cat)
    print -r -- "$selection" | /usr/bin/perl -Mstrict -Mwarnings -e '
      my %seen;
      while (<STDIN>) {
        $seen{$1} = 1 if /^\s*(\d+)\t/;
      }
      my @numbers = sort { $a <=> $b } keys %seen;
      die "Aucune saison sélectionnée.\n" unless @numbers;
      die "La saison 0 est invalide.\n" if $numbers[0] == 0;
      for my $index (1 .. $#numbers) {
        die "Les saisons sélectionnées ne sont pas contiguës.\n"
          if $numbers[$index] != $numbers[$index - 1] + 1;
      }
      print @numbers == 1 ? $numbers[0] : "$numbers[0]-$numbers[-1]";
    '
    print
    ;;

  image)
    remote_path=${1:-}
    output_path=${2:-}
    [[ -n "$remote_path" && -n "$output_path" ]] || die "Usage: ${0:t} image CHEMIN_TMBD SORTIE"
    remote_path=${remote_path#/}
    if [[ -n "$fixture_dir" ]]; then
      fixture="$fixture_dir/image-${remote_path:t}"
      [[ -f "$fixture" ]] || die "Image de test absente : $fixture"
      /bin/cp "$fixture" "$output_path"
    else
      run_curl /usr/bin/curl --fail --silent --show-error --retry 3 --retry-all-errors --remove-on-error \
        "$image_base/$remote_path" --output "$output_path"
    fi
    ;;

  *)
    print -u2 "Usage: ${0:t} search REQUÊTE | series ID | season-options ID | season ID NUMÉRO | aggregate-credits ID | normalize-seasons | image CHEMIN SORTIE"
    exit 64
    ;;
esac
