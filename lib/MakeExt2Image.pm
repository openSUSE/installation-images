#! /usr/bin/perl -w

# Create an empty ext2 fs.
#
# Usage:
#
#   use MakeExt2Image;
#
#   exported functions:
#     MakeExt2Image(file_name, size_in_kbyte, inodes);


=head1 MakeExt2Image

C<MakeExt2Image.pm> is a perl module that can be used to create Ext2 file
systems. It exports the following symbols:

=over

=item *

C<MakeExt2Image(file_name, size_in_kbyte, inodes)>

=back

=head2 Usage

use MakeExt2Image;

=head2 Description

=over

=item *

C<MakeExt2Image(file_name, size_in_kbyte, inodes)>

C<MakeExt2Image> creates an empty Ext2 file system image in C<file_name>. 
C<size_in_kbyte> is the size of the I<image>. C<inodes> is the number of inodes
the filesystem should have I<at least>.

The C<inodes> argument is optional and may be omitted.

B<Return Values>

C<MakeExt2Image> returns a list with 3 elements:

C<(blocks, block_size, inodes)>

=over

=item *

C<blocks> is the number of blocks that can be used on that file system

=item *

C<block_size> is the size of a block in bytes

=item *

C<inodes> is the actual number of usable inodes

=back

So, C<blocks * block_size> gives the usable file system size in bytes.

On any failure, C<( )> is returned.

=back

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

  system "dd if=/dev/zero of=$file_name bs=1k count=$blocks 2>/dev/null" and return ( );

  $inodes = "-N $inodes" if defined $inodes;

  system "mke2fs -q -F -b 1024 -m 0 $inodes $file_name 2>/dev/null";
  system "tune2fs -i 0 $file_name >/dev/null 2>&1";

  for ( `tune2fs -l $file_name 2>/dev/null` ) {
    $xinodes = $1 if /^Free inodes:\s*(\d+)/;
    $xblocks = $1 if /^Free blocks:\s*(\d+)/;
    $xbsize = $1 if /^Block size:\s*(\d+)/;
  }

  SUSystem "mount -oloop $file_name /mnt" and die "$Script: mount failed";

  # remove 'lost+found'
  SUSystem "rmdir /mnt/lost+found";

  for ( `df -Pk /mnt` ) {
    ($blks, $ublks ) = ($1, $2) if /^\S+\s+(\d+)\s+(\d+)/;
  }

  for ( `df -Pki /mnt` ) {
    ($inds, $uinds ) = ($1, $2) if /^\S+\s+(\d+)\s+(\d+)/;
  }

  system "sync";
  SUSystem "umount /mnt" and die "$Script: umount failed";

  return () unless $xinodes;

  return ( $blks, $xbsize, $inds )
}

1;
