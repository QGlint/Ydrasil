#!/usr/bin/env perl
use strict;
use warnings;

die "usage: $0 INPUT_BIN OUTPUT_BIN MATRIX_ITERS MATRIX_OUTER "
    . "SORT_LENGTH SORT_OUTER PRIME_LIMIT RANDOM_OUTER CRC_LENGTH CRC_OUTER\n"
    unless @ARGV == 10;
my ($input, $output, $matrix_iterations, $matrix_outer,
    $sort_length, $sort_outer, $prime_limit, $random_outer,
    $crc_length, $crc_outer) = @ARGV;

die "input and output binary paths must differ\n" if $input eq $output;
validate_range('matrix iterations', $matrix_iterations, 1, 80);
validate_range('matrix outer iterations', $matrix_outer, 1, 10);
validate_range('sort length', $sort_length, 2, 1000);
validate_range('sort outer iterations', $sort_outer, 1, 10);
validate_range('prime limit', $prime_limit, 2, 20000);
validate_range('random outer iterations', $random_outer, 1, 5000);
validate_range('CRC length', $crc_length, 2, 1024);
validate_range('CRC outer iterations', $crc_outer, 1, 400);
die "CRC length must be a power of two\n"
    if $crc_length & ($crc_length - 1);

open my $in, '<:raw', $input or die "open $input: $!\n";
local $/;
my $image = <$in>;
close $in;

my @changes;

sub validate_range {
    my ($name, $value, $minimum, $maximum) = @_;
    die "$name must be an integer in the range $minimum..$maximum\n"
        unless $value =~ /^\d+$/ && $value >= $minimum && $value <= $maximum;
}

sub addi_word {
    my ($rd, $rs1, $immediate) = @_;
    die "addi immediate $immediate is out of range\n"
        if $immediate < -2048 || $immediate > 2047;
    return (($immediate & 0xfff) << 20) | ($rs1 << 15) | ($rd << 7) | 0x13;
}

sub lui_word {
    my ($rd, $upper) = @_;
    return (($upper & 0xfffff) << 12) | ($rd << 7) | 0x37;
}

sub li_word {
    my ($rd, $value) = @_;
    return addi_word($rd, 0, $value);
}

sub li_pair {
    my ($rd, $value) = @_;
    my $upper = ($value + 0x800) >> 12;
    my $lower = $value - ($upper << 12);
    return (lui_word($rd, $upper), addi_word($rd, $rd, $lower));
}

sub patch_word {
    my ($offset, $expected, $new, $description) = @_;
    die sprintf("image is too short for instruction offset 0x%x\n", $offset)
        if $offset + 4 > length($image);
    my $word = unpack('V', substr($image, $offset, 4));
    die sprintf(
        "%s: unexpected instruction 0x%08x at offset 0x%x "
        . "(expected 0x%08x)\n",
        $description, $word, $offset, $expected,
    ) unless $word == $expected;
    substr($image, $offset, 4, pack('V', $new));
    push @changes, sprintf("0x%x %08x->%08x %s",
        $offset, $expected, $new, $description);
}

sub patch_li_pair {
    my ($offset, $rd, $expected_value, $new_value, $description) = @_;
    my @expected = li_pair($rd, $expected_value);
    my @new = li_pair($rd, $new_value);
    patch_word($offset, $expected[0], $new[0], "$description upper");
    patch_word($offset + 4, $expected[1], $new[1], "$description lower");
}

sub next_random_state {
    my ($state, $value) = @_;
    return $value % 2 == 0 ? 1 : 2 if $state == 0;
    return $value % 3 == 0 ? 2 : 3 if $state == 1;
    return $value % 5 == 0 ? 3 : 0 if $state == 2;
    return $value % 7 != 0 ? 1 : 0 if $state == 3;
    die "invalid random state $state\n";
}

sub random_checksum {
    my ($outer_iterations, $perturbed) = @_;
    my $state = $perturbed ? 1 : 0;
    my $checksum = 0;
    for (1 .. $outer_iterations) {
        for my $index (0 .. 255) {
            my $value = $perturbed
                ? 19 * $index + 31
                : 17 * $index + 23;
            $state = next_random_state($state, $value);
            $checksum = ($checksum + ($index + 1) * $state) & 0xffffffff;
        }
    }
    return $checksum;
}

my $a5 = 15;
my $a4 = 14;
my $a2 = 12;
my $a1 = 11;

# CRC memory stress: keep the restore-and-recheck validation, but shorten both
# its buffer walk and outer repetitions. The two address masks track length.
patch_word(0x500, lui_word($a5, 1), li_word($a5, $crc_length),
    'CRC fill length');
for my $offset (0x540, 0x5b4, 0x628) {
    patch_word($offset, lui_word($a1, 1), li_word($a1, $crc_length),
        'CRC checksum length');
}
for my $offset (0x57c, 0x5f0) {
    patch_li_pair($offset, $a4, 4095, $crc_length - 1,
        'CRC mutation index mask');
}
patch_word(0x678, li_word($a5, 399), li_word($a5, $crc_outer - 1),
    'CRC outer limit');

# Random stress: preserve its fixed-result check by calculating the expected
# checksum for the shortened loop. The perturbed pass must still differ.
for my $offset (0x898, 0x958) {
    patch_li_pair($offset, $a5, 4999, $random_outer - 1,
        'random outer limit');
}
my $original_random_checksum = random_checksum(5000, 0);
die sprintf("random checksum model mismatch: 0x%08x\n",
    $original_random_checksum)
    unless $original_random_checksum == 0x0f7d39a9;
my $new_random_checksum = random_checksum($random_outer, 0);
my $perturbed_random_checksum = random_checksum($random_outer, 1);
die "shortened random checksum no longer detects the perturbed pass\n"
    if $new_random_checksum == $perturbed_random_checksum;
patch_li_pair(0x8a4, $a5, $original_random_checksum, $new_random_checksum,
    'random expected checksum');

# Matrix test: all dimensions must use the same bound for initialization,
# multiplication, and result comparison.
my @matrix_offsets = map { hex($_) } qw(
    c80 ccc ce4 ddc df4 ea8 f00 f18 fe4 ffc 10bc 10d4
);
for my $offset (@matrix_offsets) {
    patch_word($offset, li_word($a5, 79),
        li_word($a5, $matrix_iterations - 1), 'matrix loop limit');
}
patch_word(0x11a0, li_word($a5, 9), li_word($a5, $matrix_outer - 1),
    'matrix outer limit');

# Prime sieve: four bounds share the same inclusive limit, and its expected
# count is derived during execution, so no fixed result constant changes.
for my $offset (0x1290, 0x12d0, 0x1358, 0x1374) {
    patch_li_pair($offset, $a5, 20000, $prime_limit, 'prime sieve limit');
}

# Sort: generation, copy, both sort implementations, comparison, and outer
# repetitions all remain consistent with the shortened array length.
for my $offset (0x173c, 0x179c, 0x17ac) {
    patch_word($offset, li_word($a1, 1000), li_word($a1, $sort_length),
        'sort length');
}
patch_word(0x1794, li_word($a5, 999), li_word($a5, $sort_length - 1),
    'sort copy limit');
patch_word(0x17bc, li_word($a2, 1000), li_word($a2, $sort_length),
    'sort comparison length');
patch_word(0x17f4, li_word($a5, 9), li_word($a5, $sort_outer - 1),
    'sort outer limit');

open my $out, '>:raw', $output or die "open $output: $!\n";
print {$out} $image;
close $out;

my $matrix_reduction = (10 * 80**3)
    / ($matrix_outer * $matrix_iterations**3);
my $sort_reduction = (10 * 1000**2) / ($sort_outer * $sort_length**2);
my $random_reduction = 5000 / $random_outer;
my $crc_reduction = (400 * 4096) / ($crc_outer * $crc_length);
printf "patched %d MF stress-loop instructions in %s\n", scalar(@changes), $output;
printf "  matrix: 80x80x80x10 -> %dx%dx%dx%d (%.0fx)\n",
    $matrix_iterations, $matrix_iterations, $matrix_iterations,
    $matrix_outer, $matrix_reduction;
printf "  sort: length 1000x10 -> %dx%d (about %.0fx for O(n^2))\n",
    $sort_length, $sort_outer, $sort_reduction;
printf "  prime: limit 20000 -> %d (about %.0fx)\n",
    $prime_limit, 20000 / $prime_limit;
printf "  random: outer 5000 -> %d (%.0fx), expected checksum 0x%08x\n",
    $random_outer, $random_reduction, $new_random_checksum;
printf "  CRC: length 4096x400 -> %dx%d (%.0fx)\n",
    $crc_length, $crc_outer, $crc_reduction;
