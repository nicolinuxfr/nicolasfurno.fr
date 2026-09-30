#!/bin/zsh
set -euo pipefail
script_dir=${0:A:h}
source "$script_dir/../lib/network.sh"

# Client minimal du SRU BnF. Les sorties sont volontairement normalisées afin
# que le reste du site ne dépende pas du vocabulaire UNIMARC.

bnf_request() {
  local schema=$1 query=$2 fixture=${BNF_FIXTURE_DIR:-}
  if [[ -n $fixture && -f "$fixture/bnf-${schema}.xml" ]]; then
    /bin/cat "$fixture/bnf-${schema}.xml"
    return
  fi
  network_curl --fail --silent --show-error --retry 2 --retry-all-errors --retry-delay 1 \
    --get 'https://catalogue.bnf.fr/api/SRU' \
    --data-urlencode 'version=1.2' \
    --data-urlencode 'operation=searchRetrieve' \
    --data-urlencode "query=$query" \
    --data-urlencode "recordSchema=$schema" \
    --data-urlencode 'maximumRecords=20'
}

xml_search_rows() {
  /usr/bin/perl -MXML::LibXML -Mutf8 -e '
    binmode STDOUT, q{:encoding(UTF-8)};
    my $doc = XML::LibXML->load_xml(IO => *STDIN);
    sub text { join q{ }, map { $_->textContent =~ s/\s+/ /gr =~ s/^\s+|\s+$//gr } @_ }
    for my $record ($doc->findnodes(q{//*[local-name()="record"]})) {
      my ($data) = $record->findnodes(q{./*[local-name()="recordData"]}); next unless $data;
      my ($ark) = $record->findnodes(q{./*[local-name()="recordIdentifier"]});
      my ($title) = $data->findnodes(q{.//*[local-name()="title"]}); next unless $title;
      my @creators = $data->findnodes(q{.//*[local-name()="creator"]});
      my ($publisher) = $data->findnodes(q{.//*[local-name()="publisher"]});
      my ($date) = $data->findnodes(q{.//*[local-name()="date"]});
      my @isbn;
      for my $description ($data->findnodes(q{.//*[local-name()="description"]})) {
        push @isbn, $1 if $description->textContent =~ /EAN\s+(\d{13})/;
      }
      if (!@isbn) {
        my ($identifier) = grep { $_->textContent =~ /ISBN/i } $data->findnodes(q{.//*[local-name()="identifier"]});
        push @isbn, $1 if $identifier && $identifier->textContent =~ /(\d[\d-]{11,}\d)/ && ($1 =~ s/\D//gr) =~ /^(\d{13})$/;
      }
      @isbn = (q{}) unless @isbn;
      my $base_title = text($title); $base_title =~ s{\s+/\s+.*$}{};
      for my $index (0 .. $#isbn) {
        my $volume = @isbn > 1 ? q{, volume } . ($index + 1) : q{};
        my $id = $ark ? text($ark) : q{};
        $id .= q{@} . $isbn[$index] if length $isbn[$index];
        print join("\t", map { $_ // q{} } ($id, $base_title . $volume, text(@creators), $publisher ? text($publisher) : q{}, $date ? text($date) : q{}, $isbn[$index] ? q{ISBN } . $isbn[$index] : q{})), "\n";
      }
    }
  '
}

xml_meta() {
  local selected_isbn=${1:-}
  BNF_SELECTED_ISBN="$selected_isbn" /usr/bin/perl -MXML::LibXML -MJSON::PP -Mutf8 -e '
    my $doc = XML::LibXML->load_xml(IO => *STDIN);
    my ($record) = $doc->findnodes(q{//*[local-name()="record" and @format="UNIMARC"]}); exit 1 unless $record;
    sub sf { my ($tag, $code) = @_; return map { $_->textContent =~ s/^\s+|\s+$//gr } $record->findnodes(qq{./*[local-name()="datafield" and \@tag="$tag"]/*[local-name()="subfield" and \@code="$code"]}); }
    sub one { my @v = sf(@_); return $v[0] // q{} }
    sub field_name {
      my ($field) = @_;
      my ($surname) = $field->findnodes(q{./*[local-name()="subfield" and @code="a"]});
      my ($given) = $field->findnodes(q{./*[local-name()="subfield" and @code="b"]});
      return q{} unless $surname;
      return join q{ }, grep { length } ($given ? $given->textContent : q{}, $surname->textContent);
    }
    my @authors;
    # 070 est le rôle « auteur ». Certaines notices récentes emploient un rôle
    # plus large : on retient alors le seul champ 700, jamais les 701/702
    # (contributeurs, traducteurs, préfaciers).
    for my $field ($record->findnodes(q{./*[local-name()="datafield" and @tag="700"]})) {
      my ($role) = $field->findnodes(q{./*[local-name()="subfield" and @code="4"]});
      next if $role && $role->textContent ne "070";
      my $name = field_name($field); push @authors, $name if length $name;
    }
    if (!@authors) {
      for my $field ($record->findnodes(q{./*[local-name()="datafield" and @tag="700"]})) {
        my $name = field_name($field); push @authors, $name if length $name;
      }
    }
    my $selected_isbn = $ENV{BNF_SELECTED_ISBN} // q{}; $selected_isbn =~ s/\D//g;
    my @isbn_fields = $record->findnodes(q{./*[local-name()="datafield" and @tag="010"]});
    my $isbn_index = 0;
    if (length $selected_isbn) {
      for my $index (0 .. $#isbn_fields) {
        my ($value) = $isbn_fields[$index]->findnodes(q{./*[local-name()="subfield" and @code="a"]});
        my $normalized = $value ? $value->textContent : q{}; $normalized =~ s/\D//g;
        $isbn_index = $index if $normalized eq $selected_isbn;
      }
    }
    my $isbn_field = $isbn_fields[$isbn_index];
    my ($isbn_node) = $isbn_field ? $isbn_field->findnodes(q{./*[local-name()="subfield" and @code="a"]}) : ();
    my ($volume_node) = $isbn_field ? $isbn_field->findnodes(q{./*[local-name()="subfield" and @code="b"]}) : ();
    my $isbn = $isbn_node ? $isbn_node->textContent : q{}; $isbn =~ s/\D//g;
    my $volume = $volume_node ? $volume_node->textContent : q{};
    my $pages = one("215", "a");
    if ($pages =~ /\(([^)]+)\)/) {
      my @counts = $1 =~ /(\d+)/g;
      $pages = $counts[$isbn_index] // $counts[0] // 0;
    } else {
      $pages = $1 if $pages =~ /(\d+)\s*p/i;
    }
    $pages = 0 unless $pages =~ /^\d+$/;
    my $publication_tag = (one("214", "c") || one("214", "d")) ? "214" : "210";
    my $date = one($publication_tag, "d"); $date =~ /((?:19|20)\d{2})/; $date = $1 // q{};
    my @translators;
    for my $field ($record->findnodes(q{./*[local-name()="datafield" and @tag="702"]})) {
      my ($surname) = $field->findnodes(q{./*[local-name()="subfield" and @code="a"]});
      my ($given) = $field->findnodes(q{./*[local-name()="subfield" and @code="b"]});
      push @translators, join q{ }, grep { length } ($given ? $given->textContent : q{}, $surname ? $surname->textContent : q{});
    }
    my $ark = $record->getAttribute("id") // q{};
    $ark =~ m{(cb[0-9a-z]+)$}; my $short_id = $1 // $ark;
    # Une notice BnF peut regrouper plusieurs volumes. Dans ce cas, ISBN est
    # identifiant public stable de edition selectionnee ; le suffixe
    # technique utilisé par la recherche ne doit pas fuiter dans les articles.
    $short_id = q{isbn:} . $isbn if length($selected_isbn) && length($isbn);
    my $title = one("200", "a");
    $title .= q{, volume } . $1 if $volume =~ /(?:vol(?:ume)?\.?)\s*(\d+)/i;
    my $collection = one("225", "a");
    my $collection_volume = one("225", "v");
    my @series = length($collection) && length($collection_volume)
      ? (join q{, }, grep { length } ($collection, $collection_volume)) : ();
    my %meta = (
      bnfId => $short_id, bnfArk => $ark,
      title => $title, authors => \@authors,
      publisher => one($publication_tag, "c"), publishedDate => $date,
      pageCount => 0 + $pages, isbn13 => (length($isbn) == 13 ? $isbn : q{}),
      language => one("101", "a"), originalLanguage => one("101", "c"),
      collection => $collection, series => \@series,
      originalTitle => one("454", "t"),
      translators => \@translators,
    );
    delete $meta{$_} for grep { !defined $meta{$_} || $meta{$_} eq q{} || (ref $meta{$_} eq q{ARRAY} && !@{$meta{$_}}) } keys %meta;
    print JSON::PP->new->canonical->utf8->encode(\%meta), "\n";
  '
}

case ${1:-} in
  search)
    shift
    # La saisie peut contenir un auteur en plus du titre (par exemple
    # « sanderson voie des rois »). Une recherche limitée au champ titre ne
    # trouve alors aucune notice et provoque un repli trompeur vers l'édition
    # originale dans les catalogues internationaux.
    bnf_request dublincore "bib.anywhere all \"$*\"" | xml_search_rows
    ;;
  record)
    [[ -n ${2:-} ]] || exit 2
    raw_id=$2
    selected_isbn=''
    if [[ $raw_id == *@* ]]; then
      selected_isbn=${raw_id##*@}
      id=${raw_id%@*}
    else
      id=$raw_id
    fi
    [[ $id == ark:* ]] || id="ark:/12148/$id"
    bnf_request unimarcXchange "bib.persistentid all \"$id\"" | xml_meta "$selected_isbn"
    ;;
  isbn)
    [[ -n ${2:-} ]] || exit 2
    bnf_request unimarcXchange "ISBN adj \"$2\"" | xml_meta
    ;;
  *) print -u2 'Usage : bnf.sh search <titre> | record <ark> | isbn <isbn>'; exit 2 ;;
esac
