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
  my ($image, $name, $size, $image2);

  $name = $image = shift;

  $name =~ s#^.*/##;

  $size = -s $image;

  return if !$size || !$name;

  $image2 = sprintf("%s %d", $image, $size >> 10);

  die "$Script: $!" unless rename $image, $image2;

  print "compressing $image...\n";

  die "$Script: gzip failed" if system "gzip -f9N '$image2'";

  die "$Script: $!" unless rename "$image2.gz", $image;

  return -s $image;
}

1;
