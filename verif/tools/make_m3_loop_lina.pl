#!/usr/bin/env perl
use strict;
use warnings;

die "usage: $0 INPUT_BIN OUTPUT_BIN SCALE\n" unless @ARGV == 3;
my ($input, $output, $scale) = @ARGV;
die "scale must be a positive integer\n"
    unless $scale =~ /^\d+$/ && $scale > 0;

open my $in, '<:raw', $input or die "open $input: $!\n";
local $/;
my $image = <$in>;
close $in;

# Scale every loop dimension by the same factor. This preserves the original
# 80:10 trip-count ratio and keeps matrix dimensions mutually consistent.
my @matrix_offsets = map { hex($_) } qw(
    a38 a84 a9c b94 bac c60 cb8 cd0 d9c db4 e74 e8c
);
my $outer_offset = hex('f58');
my @loops = ((map { [$_, 79] } @matrix_offsets), [$outer_offset, 9]);
my @scaled_summaries;

for my $loop (@loops) {
    my ($offset, $expected_limit) = @$loop;
    die sprintf("image is too short for offset 0x%x\n", $offset)
        if $offset + 4 > length($image);

    my $word = unpack('V', substr($image, $offset, 4));
    die sprintf("unexpected instruction 0x%08x at loop offset 0x%x\n",
                $word, $offset)
        unless ($word & 0x000fffff) == 0x00000793;

    my $actual_limit = ($word >> 20) & 0xfff;
    die sprintf("unexpected loop limit %d at offset 0x%x (expected %d)\n",
                $actual_limit, $offset, $expected_limit)
        unless $actual_limit == $expected_limit;

    my $original_iterations = $expected_limit + 1;
    my $scaled_iterations = int(($original_iterations + $scale - 1) / $scale);
    my $scaled_limit = $scaled_iterations - 1;
    my $new = (($scaled_limit & 0xfff) << 20) | 0x00000793;
    substr($image, $offset, 4, pack('V', $new));
    push @scaled_summaries,
        sprintf("0x%x %d->%d", $offset, $original_iterations, $scaled_iterations);
}

open my $out, '>:raw', $output or die "open $output: $!\n";
print {$out} $image;
close $out;

printf "linearly scaled all %d M3 loop dimensions by %dx (%s) in %s\n",
    scalar(@loops), $scale, join(', ', @scaled_summaries), $output;
