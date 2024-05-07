#! /usr/bin/perl

=head1 NAME

CompressImage -  compress image file.

=head1 SYNOPSIS

  use CompressImage;

  # compress "foo.img" using XZ compression
  CompressImage("foo.img", "xz");

=head1 DESCRIPTION

This module compresses an image file.

=head1 INTERFACE

  CompressImage(image_name, type);

Supported types are "gzip" and "xz". If not type is specified "gzip" is assumed.

CompressImage returns the compressed file size on success; if compression fails,
it will call die with a suitable error message.

CompressImage has some magic that will append the image size to the filename before compression
so it gets stored in the gzip header. That information was used by the installer to get size info
for transport protocols that don't have any (like tftp).

=cut


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
  $prog_opt = '--threads=0 -9 --check=crc32 -cf' if $prog eq 'xz';

  die "$Script: $prog failed" if system "$prog $prog_opt '$image2' >'$image2.tmp'";

  die "$Script: $!" unless rename "$image2.tmp", $image;
  die "$Script: $!" unless unlink $image2;

  return -s $image;
}

1;
