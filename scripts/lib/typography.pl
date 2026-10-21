#!/usr/bin/perl

use strict;
use warnings;
use utf8;
use open qw(:std :encoding(UTF-8));

local $/;
my $text = <STDIN> // '';

sub french_typography {
    my ($value) = @_;
    $value =~ s/['‘]/’/g;
    $value =~ s/\.{3}/…/g;
    $value =~ s{"([^"\n]+)"|“([^”\n]+)”|„([^“\n]+)“}{
        '«' . ($1 // $2 // $3) . '»'}ge;
    # Espaces insécables à l’intérieur des guillemets et avant les deux-points.
    $value =~ s/«[\h]*/«\x{a0}/g;
    $value =~ s/[\h]*»/\x{a0}»/g;
    # Conserve les heures et rapports numériques (12:30, 16:9).
    $value =~ s/(?<!\d)[\h]*:|[\h]+:/\x{a0}:/g;
    $value =~ s/\x{a0}:[\h]*(?=\S)/\x{a0}: /g;
    # Espace fine insécable avant ; ! ?, y compris les groupes ?!.
    $value =~ s/[\h]*([;!?]+)/\x{202f}$1/g;
    $value =~ s/([\(\[])[\h]+/$1/g;
    $value =~ s/[\h]+([\)\],.])/$1/g;
    # Un tiret isolé entre des mots est un tiret d’incise, pas un trait d’union.
    $value =~ s/[\h]+--?[\h]+/ — /g;
    return $value;
}

print french_typography($text);
