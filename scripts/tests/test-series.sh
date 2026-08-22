#!/bin/zsh

set -euo pipefail

test_dir=${0:A:h}
scripts_dir=${test_dir:h}
project=$(/usr/bin/mktemp -d "${TMPDIR:-/tmp}/nicolasfurno-generator-test.XXXXXX")
trap '/bin/rm -rf -- "$project"' EXIT INT TERM

/bin/mkdir -p "$project/content/serie" "$project/themes" "$project/fixtures"
/bin/cp -R "$scripts_dir/../data" "$project/data"
/bin/ln -s "$scripts_dir/../themes/nicolasfurno" "$project/themes/nicolasfurno"
/bin/cp "$test_dir"/fixtures/*.json "$project/fixtures/"
/usr/bin/sips -s format jpeg -z 1600 1600 "$scripts_dir/../themes/nicolasfurno/static/img/icon-512.png" \
  --out "$project/fixtures/image-poster.jpg" >/dev/null
/usr/bin/sips -s format jpeg -z 1500 1000 "$scripts_dir/../themes/nicolasfurno/static/img/icon-512.png" \
  --out "$project/fixtures/image-season-poster.jpg" >/dev/null
print -r -- $'baseURL = "https://example.test"\ntheme = "nicolasfurno"\ndefaultContentLanguage = "fr"' > "$project/hugo.toml"

export TMDB_FIXTURE_DIR="$project/fixtures"
export HUGO_TMDB=test

whole=$(
  "$scripts_dir/categories/serie.sh" generate --root "$project" --id 42 --network 'Test TV' \
    --slug 'serie-entiere-test' --seasons all
)
[[ -f "$whole" && -f "${whole:h}/meta.json" && -f "${whole:h}/cast.json" && -f "${whole:h}/seasons.json" ]]
[[ -f "${whole:h}/serie-test.jpg" ]]
jq -e '[.[].season_number] == [1,2]' "${whole:h}/seasons.json" >/dev/null
jq -e '
  all(.[ ];
    (keys | sort) == ["aggregate_credits", "air_date", "episodes", "season_number"]
    and all(.episodes[]; (keys | sort) == ["runtime"])
    and all(.aggregate_credits.cast[]; (keys | sort) == ["id", "name", "order"])
  )
' "${whole:h}/seasons.json" >/dev/null
! /usr/bin/grep -q '^saison:' "$whole"

first=$(
  "$scripts_dir/categories/serie.sh" generate --root "$project" --id 42 --network 'Test TV' \
    --slug 'serie-test' --seasons 1
)
[[ -f "${first:h}/seasons.json" && ! -f "${first:h}/cast.json" ]]
[[ -f "${first:h}/serie-test-1.jpg" ]]
first_poster_width=$(/usr/bin/sips -g pixelWidth "${first:h}/serie-test-1.jpg" | /usr/bin/awk '/pixelWidth/ {print $2}')
[[ "$first_poster_width" == 1000 ]]
/usr/bin/grep -q '^saison: \[1\]$' "$first"
jq -e 'length == 1 and .[0].season_number == 1' "${first:h}/seasons.json" >/dev/null

range=$(
  "$scripts_dir/categories/serie.sh" generate --root "$project" --id 42 --network 'Test TV' \
    --slug 'serie-test-saisons-1-2' --seasons 1-2 --no-image
)
/usr/bin/grep -q '^saison: \[1,2\]$' "$range"
jq -e '[.[].season_number] == [1,2]' "${range:h}/seasons.json" >/dev/null

if "$scripts_dir/categories/serie.sh" generate --root "$project" --id 42 --network 'Test TV' \
    --slug 'serie-test' --seasons 1 --no-image >/dev/null 2>&1; then
  print -u2 'La collision de dossier aurait dû être refusée.'
  exit 1
fi

if "$scripts_dir/categories/serie.sh" generate --root "$project" --id 42 --network 'Test TV' \
    --slug 'selection-invalide' --seasons 1,2 --no-image >/dev/null 2>&1; then
  print -u2 'Une sélection non contiguë aurait dû être refusée.'
  exit 1
fi

title=$("$scripts_dir/categories/serie.sh" title 'Série de test' 'Test TV' 1-2)
[[ "$title" == '*Série de test*, Test TV (saisons 1 et 2)' ]]

first_season_title=$("$scripts_dir/categories/serie.sh" title 'Série de test' 'Test TV' 1)
[[ "$first_season_title" == '*Série de test*, Test TV' ]]

hugo_bin=${HUGO_BIN:-${commands[hugo]:-/opt/homebrew/bin/hugo}}
"$hugo_bin" --source "$project" --destination "$project/public" --logLevel warn >/dev/null
/usr/bin/grep -q '4 épisodes de 40 à 45' "$project/public/serie/serie-entiere-test/index.html"

print 'Tests du générateur réussis.'
