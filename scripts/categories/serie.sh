#!/bin/zsh

set -euo pipefail

script_dir=${0:A:h}
lib_dir=${script_dir:h}/lib
services_dir=${script_dir:h}/services
script_path=${0:A}
script_name=${0:t}
repo_root=${ARTICLE_ROOT:-${script_dir:h:h}}
source "$lib_dir/article.sh"

series_title() {
  local name=$1 network=$2 selection=$3 start end
  case "$selection" in
    all|1) print -r -- "*$name*, $network" ;;
    <->)
      (( selection > 0 )) || article_die 'La saison 0 est invalide.'
      print -r -- "*$name*, $network (saison $selection)"
      ;;
    <->-<->)
      start=${selection%-*}; end=${selection#*-}
      (( start > 0 && start < end )) || article_die 'La plage de saisons est invalide.'
      if (( end == start + 1 )); then
        print -r -- "*$name*, $network (saisons $start et $end)"
      else
        print -r -- "*$name*, $network (saisons $start à $end)"
      fi
      ;;
    *) article_die "Sélection de saisons invalide : $selection" ;;
  esac
}

series_compact_seasons() {
  jq --compact-output --sort-keys -s '
    sort_by(.season_number)
    | map({
        air_date,
        season_number,
        episodes: [.episodes[] | {runtime}],
        aggregate_credits: {cast: [.aggregate_credits.cast[] | {id, name, order}]}
      })
  ' "$@"
}

series_generate() {
  local output_root=$repo_root id='' network='' requested_slug='' selection=''
  local requested_name=''
  local skip_image=false minimum_width=${TMDB_MIN_POSTER_WIDTH:-1000}
  local whole=false season_start=0 season_end=0
  local slug target stage created=false name image_basename title season_line title_json
  local number season_file poster_path extension candidate width image_saved
  local -a season_files season_numbers poster_paths attempted_paths

  while (( $# > 0 )); do
    case "$1" in
      --id) id=${2:-}; shift 2 ;;
      --network) network=${2:-}; shift 2 ;;
      --name) requested_name=${2:-}; shift 2 ;;
      --slug) requested_slug=${2:-}; shift 2 ;;
      --seasons) selection=${2:-}; shift 2 ;;
      --root) output_root=${2:-}; shift 2 ;;
      --no-image) skip_image=true; shift ;;
      *) article_die "Usage : $script_name generate --id ID --network DIFFUSEUR --name TITRE --slug SLUG --seasons all|N|N-M [--root DOSSIER] [--no-image]" ;;
    esac
  done

  [[ $id == <-> ]] || article_die 'Identifiant TMDB invalide.'
  [[ -n $network && -n $requested_slug && -n $selection ]] || article_die 'Paramètres de génération incomplets.'
  [[ -f "$output_root/hugo.toml" ]] || article_die "Projet Hugo introuvable : $output_root"
  slug=$(print -rn -- "$requested_slug" | "$lib_dir/slugify.pl" sanitize)
  target="$output_root/content/serie/$slug"
  [[ ! -e $target ]] || article_die "Le dossier existe déjà : $target"

  case "$selection" in
    all) whole=true ;;
    <->) season_start=$selection; season_end=$selection ;;
    <->-<->)
      season_start=${selection%-*}; season_end=${selection#*-}
      (( season_start <= season_end )) || article_die 'La plage de saisons doit être croissante.'
      ;;
    *) article_die "Sélection non contiguë ou invalide : $selection" ;;
  esac
  $whole || (( season_start > 0 && season_end > 0 )) || article_die "La saison 0 n'est pas prise en charge."

  stage=$(/usr/bin/mktemp -d "${TMPDIR:-/tmp}/nicolasfurno-series.XXXXXX")
  cleanup_series_generation() {
    local exit_status=$?
    /bin/rm -rf -- "$stage"
    if (( exit_status != 0 )) && $created && [[ -d $target ]]; then
      /bin/rm -rf -- "$target"
    fi
    exit $exit_status
  }
  trap cleanup_series_generation EXIT INT TERM

  "$services_dir/tmdb-tv.sh" series "$id" > "$stage/meta.json"
  name=${requested_name:-$(jq -er '.name | select(type == "string" and length > 0)' "$stage/meta.json")}
  image_basename=$(print -rn -- "$name" | "$lib_dir/slugify.pl" propose)

  if $whole; then
    title=$(series_title "$name" "$network" all)
    "$services_dir/tmdb-tv.sh" aggregate-credits "$id" > "$stage/cast.json"
    season_numbers=($(jq -r '.seasons[] | select(.season_number > 0 and .air_date != null) | .season_number' "$stage/meta.json"))
    (( ${#season_numbers} > 0 )) || article_die "Aucune saison diffusée n'est disponible pour cette série."
    for number in "${season_numbers[@]}"; do
      season_file="$stage/season-$number.json"
      "$services_dir/tmdb-tv.sh" season "$id" "$number" > "$season_file" || article_die "Saison TMDB $number indisponible."
      season_files+=("$season_file")
    done
    series_compact_seasons "${season_files[@]}" > "$stage/seasons.json"
    poster_paths=($(jq -r '.poster_path // empty' "$stage/meta.json"))
  else
    image_basename="$image_basename-$selection"
    for (( number = season_start; number <= season_end; number++ )); do
      season_file="$stage/season-$number.json"
      "$services_dir/tmdb-tv.sh" season "$id" "$number" > "$season_file" || article_die "Saison TMDB $number indisponible."
      season_files+=("$season_file")
    done
    series_compact_seasons "${season_files[@]}" > "$stage/seasons.json"
    title=$(series_title "$name" "$network" "$selection")
    poster_paths=($(jq -r '.poster_path // empty' "$season_files[1]") $(jq -r '.poster_path // empty' "$stage/meta.json"))
  fi

  if ! $skip_image; then
    image_saved=false
    for poster_path in "${poster_paths[@]}"; do
      [[ -n $poster_path && ${attempted_paths[(Ie)$poster_path]} -eq 0 ]] || continue
      attempted_paths+=("$poster_path")
      extension=${poster_path:e:l}; [[ $extension == (jpg|jpeg|png|webp) ]] || extension=jpg
      candidate="$stage/poster.$extension"
      if "$services_dir/tmdb-tv.sh" image "$poster_path" "$candidate"; then
        width=$(/usr/bin/sips -g pixelWidth "$candidate" 2>/dev/null | /usr/bin/awk '/pixelWidth/ {print $2}')
        [[ $width == <-> && $width -ge $minimum_width ]] && { image_saved=true; break; }
      fi
      /bin/rm -f -- "$candidate"
    done
    $image_saved || print -u2 "Avertissement : aucune affiche TMDB d'au moins $minimum_width px de large n'a été trouvée."
  fi

  /bin/mkdir -p -- "$target"
  created=true
  title_json=$(print -rn -- "$title" | jq -Rs .)
  season_line=''
  if ! $whole; then
    (( season_start == season_end )) && season_line="saison: [$season_start]" || season_line="saison: [$season_start,$season_end]"
  fi
  TITLE_JSON=$title_json ARTICLE_DATE="$(/bin/date -Iseconds)" TMDB_ID=$id SEASON_LINE=$season_line /usr/bin/perl -e '
    print "---\n";
    print "title: $ENV{TITLE_JSON}\n";
    print "date: $ENV{ARTICLE_DATE}\n";
    print "tmdb: $ENV{TMDB_ID}\n";
    print "$ENV{SEASON_LINE}\n" if length $ENV{SEASON_LINE};
    print "---\n\n";
  ' > "$target/index.md"
  /bin/cp "$stage/meta.json" "$stage/seasons.json" "$target/"
  $whole && /bin/cp "$stage/cast.json" "$target/cast.json"
  for candidate in "$stage"/poster.*(N); do
    /bin/cp "$candidate" "$target/$image_basename.${candidate:e:l}"
  done

  /bin/rm -rf -- "$stage"
  trap - EXIT INT TERM
  print -r -- "$target/index.md"
}

usage() {
  print "Usage: $script_name"
  print
  print "Assistant interactif de création d'un article de série avec Gum et fzf."
}

if (( $# > 0 )); then
  case "$1" in
    generate) shift; series_generate "$@"; exit 0 ;;
    title)
      shift
      (( $# == 3 )) || { usage >&2; exit 64; }
      series_title "$1" "$2" "$3"
      exit 0
      ;;
    -h|--help) usage; exit 0 ;;
    *) usage >&2; exit 64 ;;
  esac
fi

article_require_tools
[[ -x "$services_dir/tmdb-tv.sh" ]] || article_die "Client TMDB introuvable : $services_dir/tmdb-tv.sh"

new_search_label='↻ Nouvelle recherche…'
retry_query=''
while true; do
  query=$retry_query
  retry_query=''
  while [[ -z "$query" ]]; do
    query=$(
      "$article_gum_bin" input \
        --header 'Quel titre ?' \
        --placeholder 'Nom de la série' \
        --value "$query" \
        --width 60
    ) || article_cancel
  done

  if search_results=$("$services_dir/tmdb-tv.sh" search "$query"); then
    :
  else
    search_status=$?
    if (( search_status == 3 )); then
      retry_query=$query
      print
      "$article_gum_bin" style --foreground 214 'Aucun résultat : corrige ou remplace la recherche.'
      print
      continue
    fi
    exit "$search_status"
  fi
  result_count=$(print -r -- "$search_results" | /usr/bin/awk 'END { print NR }')
  if (( result_count == 1 )); then
    selected=$(print -r -- "$search_results" | /usr/bin/sed -n '1p')
  else
    choices=$(print -r -- "$search_results"$'\n'"new-search"$'\t'"$new_search_label")
    filter_height=$(( ${LINES:-24} > 12 ? ${LINES:-24} - 4 : 12 ))
    selected=$(
      print -r -- "$choices" | "$article_fzf_bin" \
        --delimiter $'\t' \
        --with-nth 2 \
        --header 'Quelle série ?' \
        --prompt 'Filtrer les résultats > ' \
        --height "$filter_height" \
        --layout reverse \
        --border \
        --no-sort
  ) || article_cancel
  fi
  [[ -n "$selected" ]] || article_cancel
  id=${selected%%$'\t'*}
  search_name=${selected#*$'\t'}
  search_name=$(print -r -- "$search_name" | /usr/bin/perl -CS -Mutf8 -pe 's/\s+\(\d{4}\)\s*$//')
  [[ $id == new-search ]] && continue
  [[ -n "$id" ]] || article_die "Impossible de retrouver l’identifiant TMDB de « $selected »."
  break
done

metadata=$("$services_dir/tmdb-tv.sh" series "$id")
name=${search_name:-$(print -r -- "$metadata" | jq -er '.name | select(type == "string" and length > 0)')}
network=$(print -r -- "$metadata" | jq -er '.networks[0].name | select(type == "string" and length > 0)') \
  || article_die "Aucun diffuseur TMDB n'est disponible pour « $name »."
series_type=$(print -r -- "$metadata" | jq -r '.type // empty')
season_count=$(print -r -- "$metadata" | jq '[.seasons[] | select(.season_number > 0 and .episode_count > 0)] | length')

season_selection=all
if [[ "$series_type" != 'Miniseries' ]] && (( season_count > 1 )); then
  season_options=$("$services_dir/tmdb-tv.sh" season-options "$id")
  season_choices=$(print -r -- $'all\tToutes les saisons\n'"$season_options")
  selected_seasons=$(
    print -r -- "$season_choices" | "$article_fzf_bin" \
      --multi \
      --bind 'space:toggle' \
      --delimiter $'\t' \
      --with-nth 2.. \
      --nth 2.. \
      --header $'Quelles saisons pour « '"$name"$' » ?\nEspace sélectionne, Entrée valide.' \
      --prompt 'Filtrer les saisons > ' \
      --height 15 \
      --layout reverse \
      --border \
      --no-sort
  ) || article_cancel
  [[ -n "$selected_seasons" ]] || article_cancel
  if print -r -- "$selected_seasons" | /usr/bin/grep -q $'^all\t'; then
    season_selection=all
  else
    season_selection=$(print -r -- "$selected_seasons" | "$services_dir/tmdb-tv.sh" normalize-seasons)
  fi
fi

case "$season_selection" in
  all) season_identity=__absent__ ;;
  <->) season_identity="[$season_selection]" ;;
  <->-<->) season_identity="[${season_selection%-*},${season_selection#*-}]" ;;
esac
article_check_existing serie tmdb "$id" saison "$season_identity"

title=$(series_title "$name" "$network" "$season_selection")
base_title=$(series_title "$name" "$network" all)
base_slug=$(print -rn -- "$base_title" | "$lib_dir/slugify.pl" propose)
case "$season_selection" in
  all|1)
    suggested_slug=$base_slug
    ;;
  <->|<->-<->)
    suggested_slug="${base_slug}-saison-${season_selection}"
    ;;
esac

slug=''
while [[ -z "$slug" ]]; do
  slug=$(
    "$article_gum_bin" input \
      --header 'Changer le slug ?' \
      --value "$suggested_slug" \
      --width 80
  ) || article_cancel
  if [[ -n "$slug" ]]; then
    slug=$(print -rn -- "$slug" | "$lib_dir/slugify.pl" sanitize)
  fi
done

target_dir="$repo_root/content/serie/$slug"
[[ ! -f "$target_dir/index.md" ]] || article_offer_existing "$target_dir/index.md" \
  'Le dossier correspondant à ce slug existe déjà :'

index_file=$(
  "$script_path" generate \
    --id "$id" \
    --network "$network" \
    --name "$name" \
    --slug "$slug" \
    --seasons "$season_selection"
)

print
"$article_gum_bin" style --bold --foreground 42 'Article créé'
article_open "$index_file"
