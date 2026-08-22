#!/bin/zsh
set -euo pipefail
script_dir=${0:A:h}
lib_dir=${script_dir:h}/lib
services_dir=${script_dir:h}/services
source "$lib_dir/article.sh"
article_require_tools

book_cover() {
  local meta=$1 target=$2 image=$3 isbn query response status cover key=${HUGO_GOOGLE_BOOKS:-}
  isbn=$(print -r -- "$meta" | jq -r '.isbn13 // empty')
  query=${isbn:+isbn:$isbn}
  [[ -n $query ]] || query=$(print -r -- "$meta" | jq -r '"intitle:" + .title')
  response=$(/usr/bin/curl --silent --location --retry 2 --retry-all-errors --retry-delay 1 \
    --get 'https://www.googleapis.com/books/v1/volumes' --data-urlencode "q=$query" \
    --data-urlencode maxResults=1 ${key:+--data-urlencode "key=$key"} \
    --write-out $'\n%{http_code}' 2>/dev/null || true)
  status=${response##*$'\n'}
  response=${response%$'\n'*}
  if [[ $status != 200 ]]; then
    [[ $status == 429 ]] && print -u2 'Couverture non récupérée : quota Google Books atteint.'
    return 0
  fi
  cover=$(print -r -- "$response" | jq -r '.items[0].volumeInfo.imageLinks.extraLarge // .items[0].volumeInfo.imageLinks.large // .items[0].volumeInfo.imageLinks.medium // .items[0].volumeInfo.imageLinks.thumbnail // empty' 2>/dev/null || true)
  [[ -n $cover ]] || return 0
  /usr/bin/curl --fail --silent --show-error --location --remove-on-error "$cover" --output "$target/$image" 2>/dev/null || return 0
}

book_image_search() {
  local meta=$1 query encoded
  query=$(print -r -- "$meta" | jq -r '[.title, ((.authors // []) | join(" ")), .publisher] | map(select(. != null and . != "")) | join(" ")')
  encoded=$(print -rn -- "$query" | jq -sRr @uri)
  if "$article_gum_bin" confirm --default=false 'Aucune couverture trouvée. Ouvrir une recherche d’images ?' 2>/dev/null; then
    /usr/bin/open "https://kagi.com/images?q=$encoded&no_ai=1&size=wallpaper"
  fi
}

book_is_complete() {
  print -r -- "$1" | jq -e '(.title // "") != "" and ((.authors // []) | length) > 0 and (.publisher // "") != "" and (.publishedDate // "") != "" and ((.pageCount // 0) > 0)' >/dev/null
}

book_enrich_with_google() {
  local meta=$1 lookup rows google_id google
  book_is_complete "$meta" && { print -r -- "$meta"; return; }
  lookup=$(print -r -- "$meta" | jq -r '[.title, ((.authors // []) | join(" "))] | join(" ")')
  rows=$("$services_dir/googlebooks.sh" search "$lookup" 2>/dev/null || true)
  google_id=$(print -r -- "$rows" | /usr/bin/awk -F '\t' 'NR == 1 { print $1 }')
  [[ -n $google_id ]] || { print -r -- "$meta"; return; }
  google=$("$services_dir/googlebooks.sh" record "$google_id" 2>/dev/null || true)
  [[ -n $google ]] || { print -r -- "$meta"; return; }
  print -r -- "$meta" "$google" | jq -sc '
    .[0] as $primary | .[1] as $fallback | $primary
    | . + {googleBooksId: $fallback.googleBooksId}
    | if ((.authors // []) | length) == 0 then .authors = ($fallback.authors // []) else . end
    | if (.publisher // "") == "" then .publisher = ($fallback.publisher // "") else . end
    | if (.publishedDate // "") == "" then .publishedDate = ($fallback.publishedDate // "") else . end
    | if (.pageCount // 0) == 0 then .pageCount = ($fallback.pageCount // 0) else . end
    | if (.isbn13 // "") == "" then .isbn13 = ($fallback.isbn13 // "") else . end'
}

query=$("$article_gum_bin" input --header 'Quel livre ?' --width 60) || article_cancel
[[ -n $query ]] || article_die 'Le titre est obligatoire.'
rows=$("$services_dir/bnf.sh" search "$query" 2>/dev/null || true)
catalog=bnf
# Le SRU BnF peut renvoyer des notices partageant seulement un mot du titre.
# Elles ne doivent pas empêcher le repli vers un catalogue d’éditions.
rows=$(print -r -- "$rows" | BOOK_QUERY="$query" /usr/bin/perl -CS -Mutf8 -F'\t' -ane '
  BEGIN {
    my %stop = map { $_ => 1 } qw(avec dans des les pour sur une);
    my $query = lc($ENV{BOOK_QUERY} // q{});
    $query =~ s/[^\pL\pN]+/ /g;
    @q = grep { length($_) > 2 && !$stop{$_} } split /\s+/, $query;
  }
  sub norm { my $s = lc shift; $s =~ s/[^\pL\pN]+/ /g; return q{ } . $s . q{ }; }
  my $title = norm($F[1] // q{});
  print if !@q || !grep { index($title, q{ } . $_ . q{ }) < 0 } @q;
')
if [[ -z $rows ]]; then
  rows=$("$services_dir/openlibrary.sh" search "$query" 2>/dev/null || true)
  catalog=openlibrary
fi
if [[ -z $rows ]]; then
  rows=$("$services_dir/googlebooks.sh" search "$query" 2>/dev/null || true)
  catalog=googlebooks
fi
rows=$(print -r -- "$rows" | /usr/bin/awk -F '\t' 'NF >= 2 {
  title=$2; sub(/ \/ .*/, "", title)
  author=$3; sub(/,.*/, "", author)
  label=title " — " (author == "" ? "auteur inconnu" : author)
  if ($5 != "") label=label " (" $5 ")"
  if ($4 != "") label=label " — " $4
  print $1 "\t" label
}')
if [[ -n $rows ]]; then
  choice=$(print -r -- "$rows" | article_pick_row 'Quel livre ?') || article_cancel
  [[ -n $choice ]] || article_cancel
  id=${choice%%$'\t'*}
  [[ -n $id ]] || article_cancel
fi
if [[ -n $rows && $catalog == bnf ]]; then
  if ! meta=$("$services_dir/bnf.sh" record "$id" 2>/dev/null); then
    article_die 'La notice BnF est indisponible. Réessaie dans quelques instants.'
  fi
  id=$(print -r -- "$meta" | jq -r '.bnfId')
elif [[ -n $rows && $catalog == openlibrary ]]; then
  if ! meta=$("$services_dir/openlibrary.sh" record "$id" "$query" 2>/dev/null); then
    article_die 'Open Library est temporairement indisponible. Réessaie dans quelques instants.'
  fi
  id=$(print -r -- "$meta" | jq -r '"ol:" + .openLibraryId')
elif [[ -n $rows ]]; then
  if ! meta=$("$services_dir/googlebooks.sh" record "$id" 2>/dev/null); then
    article_die 'Google Books est temporairement indisponible. Réessaie dans quelques instants.'
  fi
  id=$(print -r -- "$meta" | jq -r '"google:" + .googleBooksId')
else
  article_die "Aucun livre ne correspond à « $query »."
fi
article_check_existing livre id "$id"
meta=$(book_enrich_with_google "$meta")
book_is_complete "$meta" || article_die 'Les catalogues ne fournissent pas une fiche complète pour cette édition.'
name=$(print -r -- "$meta" | jq -er '.title')
authors=$(print -r -- "$meta" | jq -r '(.authors // []) | join(", ")')
title="*$name*${authors:+, $authors}"
author_slugs=()
country=''
while IFS= read -r author; do
  [[ -n $author ]] || continue
  entity_id=$("$services_dir/wikidata.sh" match "$author" 2>/dev/null || true)
  surname=''
  if [[ -n $entity_id ]]; then
    profile=$("$services_dir/wikidata.sh" profile "$entity_id" 2>/dev/null || true)
    surname=$(print -r -- "$profile" | jq -r '.surname // empty')
    [[ -z $country ]] && country=$(print -r -- "$profile" | jq -r '.country // empty')
  fi
  author_slugs+=("${surname:-$author}")
done < <(print -r -- "$meta" | jq -r '.authors[]?')
author_slugs=$(article_join "${author_slugs[@]}")
slug_title="*$name*${author_slugs:+, $author_slugs}"
slug=$(article_slug "$(print -rn -- "$slug_title" | "$lib_dir/slugify.pl" propose)") || article_cancel
file=$(article_create livre "$slug" "$title" $'id: '"$id"$'\n')
[[ -n $country ]] && article_set_frontmatter "$file" pays "${(L)country}"
target=${file:h}; print -r -- "$meta" | jq -S . > "$target/meta.json"
image="$(print -rn -- "$name" | "$lib_dir/slugify.pl" propose).jpg"
book_cover "$meta" "$target" "$image"
[[ -f $target/$image ]] && article_set_frontmatter "$file" image "$image"
[[ -f $target/$image ]] || book_image_search "$meta"
article_open "$file"
