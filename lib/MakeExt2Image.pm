#! /usr/bin/perl -w

=head1 NAME

MakeExt2Image - create ext2 file system.

=head1 SYNOPSIS

  use MakeExt2Image;

  # create a 5000 kbyte file system with 300 inodes.
  MakeExt2Image("foo.img", 5000, 300);

=head1 DESCRIPTION

Create an (empty) ext2 file system image.

=head1 INTERFACE

  MakeExt2Image(file_name, size_in_kbyte, inodes);

Create ext2 file system image; size_in_kbyte is the size of the image, inodes is the number of usable inodes.

The inodes argument is optional and may be omitted.

Note that size_in_kbyte is the size of the entire file system, not the number of usable blocks.

MakeExt2Image returns a list with 3 elements:

  (usable_blocks, block_size, inodes)

=over

=item *

usable_blocks: the number of blocks that can be used on that file system

=item *

block_size: block size in bytes

=item *

inodes: number of usable inodes

=back

On any failure, an empty list is returned.

=cut


require Exporter;
@ISA = qw ( Exporter );
@EXPORT = qw ( MakeExt2Image );

use strict 'vars';
use integer;


sub MakeExt2Image
{
  my (
    $file_name, $blocks, $inodes, $xinodes, $xblocks, $xbsize,
    $blks, $ublks, $inds, $uinds
  );

  ( $file_name, $blocks, $inodes ) = @_;

  die "Error: you must be root to build images\n" if $>;

  $blocks = 128 if $blocks < 128;
  $inodes = 64 if $inodes < 64;

  system "dd if=/dev/zero of=$file_name bs=1k count=$blocks 2>/dev/null" and return ( );

  $inodes = "-N $inodes" if defined $inodes;

  system "mke2fs -q -F -b 1024 -m 0 $inodes $file_name 2>/dev/null";
  system "tune2fs -i 0 $file_name >/dev/null 2>&1";

  for ( `tune2fs -l $file_name 2>/dev/null` ) {
    $xinodes = $1 if /^Free inodes:\s*(\d+)/;
    $xblocks = $1 if /^Free blocks:\s*(\d+)/;
    $xbsize = $1 if /^Block size:\s*(\d+)/;
  }

  system "mount -oloop $file_name /mnt" and die "$Script: mount failed";

  # remove 'lost+found'
  system "rmdir /mnt/lost+found";

  for ( `df -Pk /mnt 2>/dev/null` ) {
    ($blks, $ublks ) = ($1, $2) if /^\S+\s+(\d+)\s+(\d+)/;
  }

  for ( `df -Pki /mnt 2>/dev/null` ) {
    ($inds, $uinds ) = ($1, $2) if /^\S+\s+(\d+)\s+(\d+)/;
  }

  system "sync";
  system "umount /mnt" and die "$Script: umount failed";

  return () unless $xinodes;

  return ( $blks, $xbsize, $inds )
}

1;
