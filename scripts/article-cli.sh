#!/bin/zsh
set -euo pipefail

script_dir=${0:A:h}
repo_root=${ARTICLE_ROOT:-${script_dir:h}}
source "$script_dir/lib/network.sh"
source "$script_dir/lib/article.sh"
source "$script_dir/lib/movie.sh"
jq_bin=${commands[jq]:-}
[[ -n $jq_bin ]] || { print '{"ok":false,"error":{"code":"missing_dependency","message":"jq est manquant."}}'; exit 1; }

operation=${1:-}
request_file=$(/usr/bin/mktemp "${TMPDIR:-/tmp}/nicolasfurno-request.XXXXXX")
result_log=$(/usr/bin/mktemp "${TMPDIR:-/tmp}/nicolasfurno-result.XXXXXX")
output_file=$(/usr/bin/mktemp "${TMPDIR:-/tmp}/nicolasfurno-output.XXXXXX")
error_file=$(/usr/bin/mktemp "${TMPDIR:-/tmp}/nicolasfurno-error.XXXXXX")
prepare_log=$(/usr/bin/mktemp "${TMPDIR:-/tmp}/nicolasfurno-prepare.XXXXXX")
trap '/bin/rm -f -- "$request_file" "$result_log" "$output_file" "$error_file" "$prepare_log"' EXIT INT TERM
/bin/cat > "$request_file"
[[ -s $request_file ]] || print '{}' > "$request_file"

success() { jq -cn --argjson data "$1" '{ok:true,data:$data}'; }
failure() {
  local code=$1 message=$2
  jq -cn --arg code "$code" --arg message "$message" '{ok:false,error:{code:$code,message:$message}}'
  exit 1
}

categories_json() {
  local rows='[]' directory section label count
  for directory in "$repo_root"/content/*(/N); do
    section=${directory:t}
    [[ $section != pages && $section != .* ]] || continue
    indexes=("$directory"/*/index.md(N))
    [[ -f "$directory/_index.md" || ${#indexes} -gt 0 ]] || continue
    case $section in
      serie) label='Séries' ;; film) label='Films' ;; album) label='Albums' ;;
      livre) label='Livres' ;; jeu-video) label='Jeux vidéo' ;; photo) label='Photos' ;;
      spectacle) label='Spectacles' ;; *) label=${section//-/ } ;;
    esac
    count=${#indexes}
    rows=$(jq -cn --argjson rows "$rows" --arg id "$section" --arg label "$label" --argjson count "$count" '$rows + [{id:$id,label:$label,count:$count}]')
  done
  print -r -- "$rows" | jq -c 'sort_by(-.count)'
}

search_rows() {
  local category query rows search encoded
  category=$(jq -r '.category // ""' "$request_file")
  query=$(jq -r '.query // ""' "$request_file")
  [[ -n $query ]] || { print -u2 'La recherche est vide.'; return 64; }
  case $category in
    film) rows=$("$script_dir/services/tmdb-movie.sh" search "$query") ;;
    serie) rows=$("$script_dir/services/tmdb-tv.sh" search "$query") ;;
    livre)
      rows=$("$script_dir/services/bnf.sh" search "$query" 2>/dev/null || true)
      [[ -n $rows ]] || rows=$("$script_dir/services/openlibrary.sh" search "$query" 2>/dev/null || true)
      [[ -n $rows ]] || rows=$("$script_dir/services/googlebooks.sh" search "$query" 2>/dev/null || true)
      ;;
    album)
      search=$(network_curl --fail --silent --show-error --get 'https://itunes.apple.com/search' --data-urlencode "term=$query" --data-urlencode country=FR --data-urlencode media=music --data-urlencode entity=album --data-urlencode lang=fr_fr)
      rows=$(print -r -- "$search" | jq -r '.results[] | (.releaseDate // "")[:4] as $year | [.collectionId, (.collectionName + " — " + .artistName + (if $year == "" then "" else " (" + $year + ")" end))] | @tsv')
      ;;
    jeu-video)
      encoded=$(print -rn -- "$query" | jq -sRr @uri)
      search=$(network_curl --fail --silent --show-error "https://steamcommunity.com/actions/SearchApps/$encoded")
      rows=$(print -r -- "$search" | jq -r '.[] | [.appid, .name] | @tsv')
      ;;
    *) rows='' ;;
  esac
  print -r -- "$rows" | /usr/bin/awk -F '\t' 'NF >= 2 { label=$2; for(i=3;i<=NF;i++) label=label " — " $i; printf "%s\t%s\n", $1, label }' | jq -Rn '[inputs | split("\t") | {id:.[0],label:.[1]}]'
}

prepare_item() {
  local category id label slug seasons='[]' details='[]' metadata name type count network title authorship search lookup
  category=$(jq -r '.category // ""' "$request_file")
  id=$(jq -r '.id // "" | tostring' "$request_file")
  label=$(jq -r '.label // .title // .query // ""' "$request_file")
  if [[ -n $id ]]; then
    case $category in
      serie)
        metadata=$("$script_dir/services/tmdb-tv.sh" series "$id")
        name=$(print -r -- "$label" | /usr/bin/perl -CS -Mutf8 -pe 's/\s+\(\d{4}\)\s*$//')
        [[ -n $name ]] || name=$(print -r -- "$metadata" | jq -er '.name')
        network=$(print -r -- "$metadata" | jq -er '.networks[0].name')
        type=$(print -r -- "$metadata" | jq -r '.type // empty')
        count=$(print -r -- "$metadata" | jq '[.seasons[] | select(.season_number > 0 and .episode_count > 0)] | length')
        title=$("$script_dir/categories/serie.sh" title "$name" "$network" all)
        label=$title
        details=$(print -r -- "$metadata" | jq -c --arg network "$network" '[
          {label:"Diffuseur",value:$network},
          {label:"Titre original",value:(.original_name // "")},
          {label:"Diffusion",value:([(.first_air_date // ""),(.last_air_date // "")] | map(select(. != "")) | join(" → "))},
          {label:"Format",value:((.number_of_episodes // 0 | tostring) + " épisodes" + (if (.episode_run_time[0] // 0) > 0 then " · " + (.episode_run_time[0] | tostring) + " min" else "" end))}
        ] | map(select(.value != ""))')
        if [[ $type != Miniseries && $count -gt 1 ]]; then
          seasons=$("$script_dir/services/tmdb-tv.sh" season-options "$id" | jq -Rn '[inputs | split("\t") | {value:.[0],label:.[1]}]')
        fi
        ;;
      film)
        metadata=$("$script_dir/services/tmdb-movie.sh" movie "$id")
        name=$(print -r -- "$label" | /usr/bin/perl -CS -Mutf8 -pe 's/\s+\(\d{4}\)\s*$//')
        authorship=$(movie_authorship "$metadata" "$script_dir/services" "$script_dir/lib" "$name")
        label=$(print -r -- "$authorship" | jq -r '.title')
        details=$(print -r -- "$metadata" | jq -c --arg directors "$(print -r -- "$authorship" | jq -r '.directors')" '[
          {label:"Réalisation",value:$directors},
          {label:"Titre original",value:(.original_title // "")},
          {label:"Sortie",value:(.release_date // "")},
          {label:"Durée",value:(if (.runtime // 0) > 0 then (.runtime | tostring) + " min" else "" end)}
        ] | map(select(.value != ""))')
        slug=$(print -r -- "$authorship" | jq -r '.slugTitle' | "$script_dir/lib/slugify.pl" propose)
        ;;
      album)
        lookup=$(network_curl --fail --silent --show-error "https://itunes.apple.com/lookup?country=FR&lang=fr_fr&id=$id")
        metadata=$(print -r -- "$lookup" | jq -c '.results[0]')
        label=$(print -r -- "$metadata" | jq -r '"*" + .collectionName + "*, " + .artistName')
        details=$(print -r -- "$metadata" | jq -c '[
          {label:"Artiste",value:(.artistName // "")},
          {label:"Sortie",value:((.releaseDate // "")[:10])},
          {label:"Genre",value:(.primaryGenreName // "")},
          {label:"Morceaux",value:(if (.trackCount // 0) > 0 then (.trackCount | tostring) else "" end)}
        ] | map(select(.value != ""))')
        slug=$(prepare_slug_with_category "$category")
        ;;
      jeu-video)
        search=$(network_curl --fail --silent --show-error "https://store.steampowered.com/api/appdetails?lang=fr&appids=$id")
        metadata=$(print -r -- "$search" | jq -ce --arg id "$id" '.[$id] | select(.success == true) | .data')
        name=${label:-$(print -r -- "$metadata" | jq -er '.name')}
        label="*$name*"
        slug=$(print -rn -- "$name" | "$script_dir/lib/slugify.pl" propose)
        details=$(print -r -- "$metadata" | jq -c '[
          {label:"Développement",value:((.developers // []) | join(", "))},
          {label:"Édition",value:((.publishers // []) | join(", "))},
          {label:"Sortie",value:(.release_date.date // "")},
          {label:"Genres",value:((.genres // []) | map(.description) | join(", "))}
        ] | map(select(.value != ""))')
        ;;
      livre)
        case $id in
          cb*) metadata=$("$script_dir/services/bnf.sh" record "$id" 2>/dev/null || true) ;;
          ol:*) metadata=$("$script_dir/services/openlibrary.sh" record "$id" "$(jq -r '.query // ""' "$request_file")" 2>/dev/null || true) ;;
          *) metadata=$("$script_dir/services/googlebooks.sh" record "$id" 2>/dev/null || true) ;;
        esac
        if [[ -n $metadata ]]; then
          label=$(print -r -- "$metadata" | jq -r '.title + (if ((.authors // []) | length) > 0 then " — " + (.authors | join(", ")) else "" end)')
          details=$(print -r -- "$metadata" | jq -c '[
            {label:"Auteur",value:((.authors // []) | join(", "))},
            {label:"Édition",value:(.publisher // "")},
            {label:"Publication",value:(.publishedDate // "")},
            {label:"Pagination",value:(if (.pageCount // 0) > 0 then (.pageCount | tostring) + " pages" else "" end)},
            {label:"ISBN",value:(.isbn13 // "")}
          ] | map(select(.value != ""))')
        else
          details=$(jq -cn --arg value "$label" '[{label:"Édition sélectionnée",value:$value}]')
        fi
        slug=$(prepare_slug_with_category "$category")
        ;;
    esac
  fi
  if [[ $category == photo ]]; then
    count=$(jq '.files // [] | length' "$request_file")
    (( count > 0 )) && details=$(jq -cn --arg value "$count photo$([[ $count -gt 1 ]] && print s)" '[{label:"Import",value:$value}]')
  fi
  [[ -n $slug ]] || slug=$(print -rn -- "$label" | "$script_dir/lib/slugify.pl" propose 2>/dev/null || true)
  jq -cn --arg category "$category" --arg id "$id" --arg label "$label" --arg suggestedSlug "$slug" --argjson seasons "$seasons" --argjson details "$details" '{category:$category,id:$id,label:$label,suggestedSlug:$suggestedSlug,seasons:$seasons,details:$details}'
}

prepare_slug_with_category() {
  local category=$1 runner suggested
  runner=("$script_dir/categories/$category.sh")
  : > "$prepare_log"
  : > "$result_log"
  ARTICLE_ROOT="$repo_root" ARTICLE_NO_OPEN=true ARTICLE_RESULT_LOG="$result_log" \
    ARTICLE_PREPARE_LOG="$prepare_log" ARTICLE_SKIP_EXISTING=true ARTICLE_REQUEST_FILE="$request_file" \
    GUM_BIN="$script_dir/lib/raycast-gum.sh" FZF_BIN="$script_dir/lib/raycast-fzf.sh" \
    "${runner[@]}" >"$output_file" 2>&1 || true
  if [[ -s $prepare_log ]]; then
    suggested=$(/bin/cat "$prepare_log")
    print -rn -- "$suggested" | "$script_dir/lib/slugify.pl" sanitize
  else
    print -u2 -- "$(/usr/bin/tail -n 8 "$output_file")"
    return 1
  fi
}

create_item() {
  local category runner result_status article_path message
  category=$(jq -r '.category // ""' "$request_file")
  [[ -n $category ]] || { print -u2 'La catégorie est obligatoire.'; return 64; }
  if [[ $category == photo ]]; then
    export ARTICLE_PHOTO_FILES=$(jq -r '(.files // [])[]' "$request_file")
  fi
  if [[ -x "$script_dir/categories/$category.sh" ]]; then
    runner=("$script_dir/categories/$category.sh")
  else
    runner=("$script_dir/categories/default.sh" "$category")
  fi
  if ARTICLE_ROOT="$repo_root" ARTICLE_NO_OPEN=true ARTICLE_RESULT_LOG="$result_log" \
    ARTICLE_REQUEST_FILE="$request_file" GUM_BIN="$script_dir/lib/raycast-gum.sh" \
    FZF_BIN="$script_dir/lib/raycast-fzf.sh" "${runner[@]}" >"$output_file" 2>&1; then
    :
  else
    message=$(/usr/bin/tail -n 8 "$output_file")
    print -u2 -- "${message:-La création a échoué.}"
    return 1
  fi
  if [[ -s $result_log ]]; then
    IFS=$'\t' read -r result_status article_path < "$result_log"
    jq -cn --arg status "$result_status" --arg path "$article_path" --arg directory "${article_path:h}" '{status:$status,path:$path,directory:$directory}'
  else
    print -u2 'Le script n’a retourné aucun article.'
    return 1
  fi
}

run_operation() {
  local code=$1
  shift
  local data error
  if data=$("$@" 2>"$error_file"); then
    success "$data"
  else
    error=$(/usr/bin/tail -n 8 "$error_file")
    failure "$code" "${error:-L’opération a échoué.}"
  fi
}

case $operation in
  categories) run_operation categories_failed categories_json ;;
  search) run_operation search_failed search_rows ;;
  prepare) run_operation preparation_failed prepare_item ;;
  create) run_operation creation_failed create_item ;;
  check)
    [[ -f "$repo_root/hugo.toml" ]] || failure invalid_root 'Le dossier ne contient pas hugo.toml.'
    missing=()
    for tool in jq curl perl; do (( $+commands[$tool] )) || missing+=("$tool"); done
    (( ${#missing} == 0 )) || failure missing_dependency "Dépendances manquantes : ${(j:, :)missing}."
    success "$(jq -cn --arg root "$repo_root" '{root:$root}')"
    ;;
  *) failure usage 'Usage : article-cli.sh categories|search|prepare|create|check' ;;
esac
