#!/usr/bin/env perl
use strict;
use warnings;

my $binary = @ARGV && $ARGV[0] eq '--binary' ? shift @ARGV : 0;
die "usage: $0 [--binary] INPUT.coe OUTPUT\n" unless @ARGV == 2;
my ($input, $output) = @ARGV;

open my $in, '<', $input or die "open $input: $!\n";
local $/;
my $coe = <$in>;
close $in;

my ($radix) = $coe =~ /memory_initialization_radix\s*=\s*(\d+)\s*;/i;
die "$input: missing memory_initialization_radix\n" unless defined $radix;
die "$input: only radix 16 is supported (got $radix)\n" unless $radix == 16;

my ($vector) = $coe =~ /memory_initialization_vector\s*=\s*(.*)/is;
die "$input: missing memory_initialization_vector\n" unless defined $vector;
$vector =~ s/;.*\z//s;

my @words;
for my $token (split /[\s,]+/, $vector) {
    next unless length $token;
    die "$input: invalid vector token '$token'\n"
        unless $token =~ /\A[0-9a-fA-F]{1,8}\z/;
    push @words, hex($token);
}
die "$input: initialization vector is empty\n" unless @words;

if ($binary) {
    open my $out, '>:raw', $output or die "open $output: $!\n";
    print {$out} pack('V*', @words);
    close $out;
} else {
    open my $out, '>', $output or die "open $output: $!\n";
    printf {$out} "%08x\n", $_ for @words;
    close $out;
}

printf "converted %d words from %s to %s%s\n",
    scalar(@words), $input, $output, $binary ? ' (little-endian binary)' : '';
