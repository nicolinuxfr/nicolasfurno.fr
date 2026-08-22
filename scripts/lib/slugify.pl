#!/usr/bin/perl

use strict;
use warnings;
use utf8;
use open qw(:std :encoding(UTF-8));
use Unicode::Normalize qw(NFKD);

my ($mode) = @ARGV;
die "Usage: slugify.pl propose|sanitize\n"
    unless defined $mode && $mode =~ /\A(?:propose|sanitize)\z/;

my %stopwords = map { $_ => 1 } qw(the les des une dans avec pour sur and for);

local $/;
my $input = <STDIN> // '';
$input =~ tr/’‘‛＇/'/;

# Élisions françaises : l'été → été, d'argent → argent.
$input =~ s/(?:^|(?<=[^\pL\pN]))(?:l|d|j|m|n|qu|s|t|c)'(?=[\pL\pN])//giu;
# Possessifs anglais et autres apostrophes : Widow's → Widows, don't → dont.
$input =~ s/([\pL\pN])'s(?=$|[^\pL\pN])/${1}s/giu;
$input =~ s/'//g;

$input =~ s/œ/oe/giu;
$input =~ s/æ/ae/giu;
$input =~ s/ß/ss/giu;
$input =~ s/[øØ]/o/g;
$input =~ s/[łŁ]/l/g;
$input =~ s/[ðÐ]/d/g;
$input =~ s/[þÞ]/th/g;
$input = NFKD($input);
$input =~ s/\pM//g;
$input =~ s/[^A-Za-z0-9+]+/ /g;
$input =~ s/^\s+|\s+$//g;

my @tokens;
my @all_tokens;
for my $original (split /\s+/, $input) {
    next if $original eq '';
    my $token = lc $original;
    $token =~ s/^\++|\++$//g if $token !~ /[A-Za-z0-9]/;
    next if $token eq '';
    push @all_tokens, $token;

    if ($mode eq 'propose') {
        next if $stopwords{$token};
        my $letters = $original;
        $letters =~ s/\+//g;
        my $is_number_or_code = $token =~ /\d/;
        my $is_short_acronym = $letters =~ /\A[A-Z]{1,2}\z/;
        my $is_abbreviation = $token =~ /\A(?:st|mr|ms|dr|jr)\z/;
        next if length($token) <= 2
            && !$is_number_or_code
            && !$is_short_acronym
            && !$is_abbreviation;
    }
    push @tokens, $token;
}

# Un titre constitué uniquement de petits mots reste utilisable (Mo, Y, i/o…).
if (!@tokens && $mode eq 'propose') {
    @tokens = @all_tokens;
}

my $slug = join '-', @tokens;
$slug =~ s/-+/-/g;
$slug =~ s/^-|-$//g;
die "Impossible de produire un slug à partir de cette entrée.\n" if $slug eq '';
print "$slug\n";
