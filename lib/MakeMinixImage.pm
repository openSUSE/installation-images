#! /usr/bin/perl

# Create an empty minix fs.
#
# Usage:
#
#   use MakeMinixImage;
#
#   exported functions:
#     MakeMinixImage(file_name, size_in_kbyte, inodes);


=head1 MakeMinixImage

C<MakeMinixImage.pm> is a perl module that can be used to create Minix file
systems. It exports the following symbols:

=over

=item *

C<MakeMinixImage(file_name, size_in_kbyte, inodes)>

=back

=head2 Usage

use MakeMinixImage;

=head2 Description

=over

=item *

C<MakeMinixImage(file_name, size_in_kbyte, inodes)>

C<MakeMinixImage> creates an empty Minix file system image in C<file_name>. 
C<size_in_kbyte> is the size of the I<image>. C<inodes> is the number of inodes
the filesystem should have I<at least>.

B<Return Values>

C<MakeMinixImage> returns a list with 3 elements:

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
@EXPORT = qw ( MakeMinixImage );

use strict 'vars';
use integer;


sub MakeMinixImage
{
  my (
    $file_name, $blocks, $inodes, $xinodes, $xofs
  );

  ( $file_name, $blocks, $inodes ) = @_;

  system "dd if=/dev/zero of=$file_name bs=1k count=$blocks 2>/dev/null" and return ( );

  for ( `mkfs.minix -i $inodes $file_name` ) {
    $xinodes = $1 if /(\d+)\s*inodes/;
    $xofs = $1 if /Firstdatazone=(\d+)/
  }

  return () unless $xinodes;

  return ( $blocks - $xofs, 1024, $xinodes )
}

1;
