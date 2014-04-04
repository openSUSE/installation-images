#! /usr/bin/perl

# Usage:
#
#   use CompressImage
#
#   exported functions:
#     CompressImage();


require Exporter;
@ISA = qw ( Exporter );
@EXPORT = qw ( CompressImage );

use strict 'vars';
use integer;

sub CompressImage
{
  local $_;
  my ($image, $name, $size, $image2, $prog, $prog_opt);

  $name = $image = shift;

  $name =~ s#^.*/##;

  $prog = shift || 'gzip';

  $size = -s $image;

  return if !$size || !$name;

  $image2 = sprintf("%s %d", $image, $size >> 10);

  die "$Script: $!" unless rename $image, $image2;

  print "compressing $image...\n";

  $prog_opt = '-cf9N' if $prog eq 'gzip';
  $prog_opt = '--check=crc32 -cf' if $prog eq 'xz';

  die "$Script: $prog failed" if system "$prog $prog_opt '$image2' >'$image2.tmp'";

  die "$Script: $!" unless rename "$image2.tmp", $image;
  die "$Script: $!" unless unlink $image2;

  return -s $image;
}

1;
