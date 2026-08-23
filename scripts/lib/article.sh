#!/bin/zsh

set -euo pipefail

# `%N` reste le chemin de ce fichier lorsqu’il est chargé avec `source`.
article_library_dir=${${(%):-%N}:A:h}
article_script_dir=${article_library_dir:h}
article_repo_root=${ARTICLE_ROOT:-$article_script_dir:h}
source "$article_library_dir/people.sh"
article_gum_bin=${GUM_BIN:-${commands[gum]:-}}
article_fzf_bin=${FZF_BIN:-${commands[fzf]:-}}
article_jq_bin=${commands[jq]:-}

article_die() { print -u2 -- "$*"; exit 1 }
article_cancel() {
  # Efface le message d’annulation interne de Gum, sans ajouter de sortie.
  print -n -- $'\033[1A\033[2K\r'
  exit 0
}

article_require_tools() {
  [[ -n $article_gum_bin && -n $article_fzf_bin && -n $article_jq_bin ]] || \
    article_die 'Des outils sont manquants. Lancer : scripts/install.sh'
}

article_slug() {
  local suggested=$1 slug=''
  while [[ -z $slug ]]; do
    slug=$("$article_gum_bin" input --header 'Changer le slug ?' --value "$suggested" --width 80) || return 1
    [[ -n $slug ]] && slug=$(print -rn -- "$slug" | "$article_library_dir/slugify.pl" sanitize)
  done
  print -r -- "$slug"
}

article_open() { /usr/bin/open "${1:h}" }

article_offer_existing() {
  local index_file=$1 reason=${2:-'Un article correspondant existe déjà :'}
  local target=${index_file:h}
  print
  "$article_gum_bin" style --bold --foreground 214 'Article déjà présent'
  print -r -- "$reason"
  print -r -- "$target"
  print -r -- 'Aucun fichier n’a été créé ou modifié.'
  print
  if "$article_gum_bin" confirm 'Ouvrir ce dossier dans le Finder ?'; then
    article_open "$index_file" || print -u2 -- "Impossible d’ouvrir le dossier dans le Finder : $target"
  fi
  exit 0
}

article_find_existing() {
  local section=$1 identity_field=$2 identity_value=$3
  local qualifier_field=${4:-} qualifier_value=${5:-}
  local -a indexes
  indexes=("$article_repo_root/content/$section"/*/index.md(N))
  (( ${#indexes} > 0 )) || return 0
  IDENTITY_FIELD=$identity_field IDENTITY_VALUE=$identity_value \
    QUALIFIER_FIELD=$qualifier_field QUALIFIER_VALUE=$qualifier_value \
    /usr/bin/perl -Mstrict -Mwarnings -e '
      my ($identity_field, $identity_value, $qualifier_field, $qualifier_value) =
        @ENV{qw(IDENTITY_FIELD IDENTITY_VALUE QUALIFIER_FIELD QUALIFIER_VALUE)};
      FILE: for my $file (@ARGV) {
        open my $handle, q{<}, $file or next;
        my (%fields, $frontmatter, $delimiters);
        while (my $line = <$handle>) {
          chomp $line;
          if ($line eq q{---}) {
            $delimiters++;
            $frontmatter = $delimiters == 1;
            last if $delimiters == 2;
            next;
          }
          next unless $frontmatter;
          if ($line =~ /^([A-Za-z0-9_-]+):\s*(.*?)\s*$/) {
            my ($field, $value) = ($1, $2);
            $value =~ s/^(["\x27])(.*)\1$/$2/;
            $fields{$field} = $value;
          }
        }
        next unless defined $fields{$identity_field}
          && $fields{$identity_field} eq $identity_value;
        if (length $qualifier_field) {
          if ($qualifier_value eq q{__absent__}) {
            next if defined $fields{$qualifier_field};
          } else {
            next unless defined $fields{$qualifier_field};
            (my $actual = $fields{$qualifier_field}) =~ s/\s+//g;
            (my $expected = $qualifier_value) =~ s/\s+//g;
            next unless $actual eq $expected;
          }
        }
        print "$file\n";
        last FILE;
      }
    ' "${indexes[@]}"
}

article_check_existing() {
  local existing
  existing=$(article_find_existing "$@")
  [[ -z $existing ]] || article_offer_existing "$existing"
}

article_create() {
  local section=$1 slug=$2 title=$3 extra=${4:-}
  local target="$article_repo_root/content/$section/$slug"
  if [[ -f "$target/index.md" ]]; then
    article_offer_existing "$target/index.md" 'Le dossier correspondant à ce slug existe déjà :'
  fi
  [[ ! -e $target ]] || article_die "Le dossier existe déjà mais ne contient pas d’article valide : $target"
  /bin/mkdir -p -- "$target"
  local title_json
  title_json=$(print -rn -- "$title" | jq -Rs .)
  TITLE_JSON=$title_json EXTRA=$extra ARTICLE_DATE="$(/bin/date -Iseconds)" /usr/bin/perl -e '
    print "---\n";
    print "title: $ENV{TITLE_JSON}\n";
    print "date: ", $ENV{ARTICLE_DATE}, "\n";
    print $ENV{EXTRA};
    print "---\n\n";
  ' > "$target/index.md"
  print -r -- "$target/index.md"
}

article_set_frontmatter() {
  local file=$1 field=$2 value=$3 encoded
  encoded=$(print -rn -- "$value" | jq -Rs .)
  FIELD=$field VALUE=$encoded /usr/bin/perl -0pi -e '
    s/\n---\n\n\z/"\n$ENV{FIELD}: $ENV{VALUE}\n---\n\n"/e
      or die "Front matter final introuvable dans $ARGV.\n";
  ' "$file"
}

article_pick() {
  local header=$1
  "$article_fzf_bin" --header "$header" --prompt 'Filtrer > ' --height 15 --layout reverse --border --no-sort
}

article_pick_row() {
  local header=$1
  "$article_fzf_bin" --delimiter $'\t' --with-nth 2.. --header "$header" --prompt 'Filtrer > ' \
    --height 15 --layout reverse --border --no-sort
}

article_surnames() {
  print -r -- "$1" | /usr/bin/perl -CS -Mutf8 -e '
    my $value = <STDIN> // q{};
    chomp $value;
    my @names = split /\s*,\s*/, $value;
    print join q{, }, map { my @words = split /\s+/, $_; $words[-1] } @names;
  '
}

article_join() {
  print -r -- "${(j:, :)@}"
}
