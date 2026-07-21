#!/usr/bin/env perl
use strict;
use warnings;

die "usage: $0 INPUT_BIN OUTPUT_BIN LIMIT\n" unless @ARGV == 3;
my ($input, $output, $limit) = @ARGV;
die "limit must fit addi's signed 12-bit immediate\n"
    unless $limit =~ /^\d+$/ && $limit <= 2047;

open my $in, '<:raw', $input or die "open $input: $!\n";
local $/;
my $image = <$in>;
close $in;

my @offsets = map { hex($_) } qw(
    a38 a84 a9c b94 bac c60 cb8 cd0 d9c db4 e74 e8c f58
);
my $new = (($limit & 0xfff) << 20) | 0x00000793;

for my $offset (@offsets) {
    die sprintf("image is too short for offset 0x%x\n", $offset)
        if $offset + 4 > length($image);
    my $word = unpack('V', substr($image, $offset, 4));
    die sprintf("unexpected instruction 0x%08x at loop offset 0x%x\n",
                $word, $offset)
        unless ($word & 0x000fffff) == 0x00000793;
    substr($image, $offset, 4, pack('V', $new));
}

open my $out, '>:raw', $output or die "open $output: $!\n";
print {$out} $image;
close $out;

printf "patched %d M3 loop bounds to %d in %s\n", scalar(@offsets), $limit, $output;
