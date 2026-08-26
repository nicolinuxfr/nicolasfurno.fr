#!/bin/zsh

saga_normalize() {
  print -rn -- "$1" | /usr/bin/perl -CS -Mutf8 -MUnicode::Normalize -e '
    use feature q{fc};
    my $value = <STDIN> // q{};
    $value = fc(NFKD($value));
    $value =~ s/\pM//g;
    $value =~ s/(?:\s*[-:]?\s*(?:saga|series|collection))\s*$//i;
    $value =~ s/(?:\s*[,(:#-]?\s*(?:book|volume|vol\.?|tome)?\s*#?\d+\s*\)?)\s*$//i;
    $value =~ s/^(?:the|le|la|les)\s+//i;
    $value =~ s/[^\pL\pN]+//g;
    print $value;
  '
}

saga_existing_by_name() {
  local candidate=$1 allow_prefix=${2:-false} normalized existing label label_normalized
  normalized=$(saga_normalize "$candidate")
  [[ -n $normalized ]] || return 0
  while IFS= read -r label; do
    [[ -n $label ]] || continue
    label_normalized=$(saga_normalize "$label")
    if [[ $label_normalized == $normalized ]]; then
      print -r -- "$label"
      return 0
    fi
    if [[ $allow_prefix == true && -z ${existing:-} && ( $normalized == ${label_normalized}* || $label_normalized == ${normalized}* ) ]]; then
      existing=$label
    fi
  done < <(SAGA_ROOT="$article_repo_root" /usr/bin/perl -Mstrict -Mwarnings -e '
    for my $file (glob qq{$ENV{SAGA_ROOT}/content/*/*/index.md}) {
      open my $handle, q{<}, $file or next;
      my $lines = 0;
      while (my $line = <$handle>) {
        last if ++$lines > 20;
        if ($line =~ /^sagas:\s*["\x27]?(.*?)["\x27]?\s*$/) {
          print qq{$1\n}; last;
        }
      }
      close $handle;
    }
  ' | /usr/bin/awk '!seen[$0]++')
  [[ -z ${existing:-} ]] || print -r -- "$existing"
}

saga_existing_by_tmdb_collection() {
  local collection_id=$1 meta index label
  for meta in "$article_repo_root"/content/film/*/meta.json(N); do
    [[ $(jq -r '.belongs_to_collection.id // empty' "$meta") == $collection_id ]] || continue
    index=${meta:h}/index.md
    label=$(INDEX="$index" /usr/bin/perl -ne '
      if (/^sagas:\s*[\x22\x27]?(.*?)[\x22\x27]?\s*$/) { print $1; exit }
    ' "$index")
    [[ -z $label ]] || { print -r -- "$label"; return 0; }
  done
}

saga_weight_from_text() {
  print -rn -- "$1" | /usr/bin/perl -CS -Mutf8 -e '
    my $value = <STDIN> // q{};
    if ($value =~ /(?:#|\b(?:book|volume|vol\.?|tome)\s*)(\d+)\b/i) { print $1 }
    elsif ($value =~ /\b(\d+)\s*$/) { print $1 }
  '
}

saga_frontmatter() {
  local name=${1:-} weight=${2:-} identified=${3:-false} encoded
  [[ -n $name || $identified == true ]] || return 0
  encoded=$(print -rn -- "$name" | jq -Rs .)
  print -r -- "sagas: $encoded"
  if [[ $weight == <-> ]]; then
    print -r -- "sagas_weight: $weight"
  else
    print -r -- 'sagas_weight:'
  fi
  return 0
}
