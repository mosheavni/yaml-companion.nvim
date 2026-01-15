#!/usr/bin/env perl
# Post-process vimdoc to flatten and renumber TOC
use strict;
use warnings;

my $file = $ARGV[0] or die "Usage: $0 <file>\n";

open my $fh, '<', $file or die "Cannot open $file: $!";
my $content = do { local $/; <$fh> };
close $fh;

# Simplify tag names by removing redundant "-introduction"
$content =~ s/yaml-companion-introduction-/yaml-companion-/g;

# Replace M. prefix with yaml_companion. in API function signatures
# (the ---@mod annotation handles tags, but not the signature text)
$content =~ s/^M\./yaml_companion./gm;

# Find and replace the TOC section
$content =~ s{
  (Table\ of\ Contents\s+\*yaml-companion-table-of-contents\*\n+)
  (.*?)
  (\n={10,})
}{
  my $header = $1;
  my $toc = $2;
  my $end = $3;

  my @lines = grep { /\S/ } split /\n/, $toc;
  my $num = 1;
  my $new_toc = "";

  # First pass: collect items and find max title length
  my @items;
  for my $line (@lines) {
    if ($line =~ /\|yaml-companion-.*\|/) {
      $line =~ s/^\s*\d+\.\s*//;   # Remove existing number
      $line =~ s/^\s*-\s*//;        # Remove bullet
      if ($line =~ /^(.+?)\s+(\|yaml-companion-.*\|)$/) {
        push @items, [$1, $2];
      }
    }
  }

  # Second pass: format with aligned tags
  my $max_num_width = length(scalar @items);
  for my $item (@items) {
    my ($title, $tag) = @$item;
    my $prefix = sprintf("%*d. %s", $max_num_width, $num++, $title);
    my $padding = 60 - length($prefix);
    $padding = 2 if $padding < 2;
    $new_toc .= $prefix . (" " x $padding) . $tag . "\n";
  }

  $header . $new_toc . $end;
}sex;

open $fh, '>', $file or die "Cannot write $file: $!";
print $fh $content;
close $fh;
