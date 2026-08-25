#!/bin/zsh

# Résout uniquement la graphie d'un titre. La notice principale reste la source
# bibliographique : une traduction ou une autre édition ne doit jamais la
# remplacer silencieusement.
book_resolve_display_title() {
  /usr/bin/perl -CS -Mutf8 -MJSON::PP -MUnicode::Normalize -e '
    use feature q{fc};
    binmode STDIN, q{:raw};
    binmode STDOUT, q{:raw};
    my $input = JSON::PP->new->utf8->decode(join q{}, <STDIN>);
    my $primary = $input->{primary} // {};
    my $title = $primary->{title} // q{};
    my $language = $primary->{originalLanguage} // $primary->{language} // q{};

    sub canonical {
      my $value = fc(NFKC(shift // q{}));
      $value =~ s/[\pP\pS\s]+//g;
      return $value;
    }

    my %authors = map { canonical($_) => 1 } @{$primary->{authors} // []};
    my $primary_source = $primary->{catalogSource} // q{bnf};
    my @equivalent = ({ source => $primary_source, title => $title });
    for my $candidate (@{$input->{candidates} // []}) {
      next unless ref $candidate eq q{HASH};
      next unless length($candidate->{title} // q{});
      next unless canonical($candidate->{title}) eq canonical($title);
      my @candidate_authors = @{$candidate->{authors} // []};
      next unless @candidate_authors && grep { $authors{canonical($_)} } @candidate_authors;
      push @equivalent, $candidate;
    }

    my ($selected, $ambiguous) = ($equivalent[0], JSON::PP::false);
    if ($language ne q{fre} && @equivalent > 1) {
      my (%count, %first);
      for my $candidate (@equivalent) {
        $count{$candidate->{title}}++;
        $first{$candidate->{title}} //= $candidate;
      }
      my $best = (sort { $count{$b} <=> $count{$a} } keys %count)[0];
      my @leaders = grep { $count{$_} == $count{$best} } keys %count;
      if (@leaders == 1 && $count{$best} > 1) {
        $selected = $first{$best};
      } elsif (@equivalent == 2) {
        # À égalité, une source internationale préserve mieux la graphie du
        # titre non français que la convention de catalogage de la BnF.
        $selected = $equivalent[1];
      } else {
        $ambiguous = JSON::PP::true;
      }
    }

    print JSON::PP->new->canonical->utf8->encode({
      title => $selected->{title}, source => $selected->{source},
      ambiguous => $ambiguous, candidates => \@equivalent,
    }), qq{\n};
  '
}
