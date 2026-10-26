#!/usr/bin/perl
use strict;
use warnings;
use JSON::PP;
use Unicode::Normalize qw(NFKD);

# Ne jamais assimiler le premier résultat de recherche à l’œuvre sélectionnée.
# Les dates d’éditions et les résultats ambigus ne sont pas des preuves.
my $json = JSON::PP->new->utf8->canonical;
my $input = $json->decode(do { local $/; <STDIN> });
my $primary = $input->{primary};
sub canonical {
    my $s = lc NFKD(shift // '');
    $s =~ s/\pM//g;
    $s =~ s/[^\pL\pN]+/ /g;
    $s =~ s/^\s+|\s+$//g;
    return $s;
}
sub author { join ' ', sort split /\s+/, canonical(shift) }
# Une notice de traduction isolée peut avoir sa propre « première année ».
# Quand le titre original est connu, lui seul peut identifier l’œuvre.
my %titles = (canonical($primary->{originalTitle} || $primary->{title}) => 1);
my %authors = map { author($_) => 1 } @{$primary->{authors} // []};
my %matches;
for my $doc (@{$input->{docs} // []}) {
    next unless $titles{canonical($doc->{title})};
    my @names = @{$doc->{author_name} // []};
    next unless @names && @names == keys(%authors)
        && !grep { !$authors{author($_)} } @names;
    my $year = $doc->{first_publish_year} // '';
    next unless $year =~ /^[1-9][0-9]{3}$/;
    my $edition = $primary->{publishedDate} // '';
    next if $edition =~ /^([0-9]{4})/ && $year > $1;
    my $key = $doc->{key} // '';
    $key =~ s{^/works/}{};
    next unless $key =~ /^OL[0-9]+W$/;
    $matches{$key}{$year} = 1;
}
my @keys = keys %matches;
my $result = {};
if (@keys == 1) {
    my @years = keys %{$matches{$keys[0]}};
    if (@years == 1) {
        $result = { publishedDate => "$years[0]" };
    }
}
print $json->encode($result), "\n";
