#! /usr/bin/perl

# Usage:
#
#   use Conv2Image;
#
#   exported functions:
#     Conv2Image();


=head1 Conv2Image

=cut


require Exporter;
@ISA = qw ( Exporter );
@EXPORT = qw ( Conv2Image );

use strict 'vars';
use integer;

sub Conv2Image
{
  my (
    $image, $dir, $fs, $x_k, $x_inodes, $c_k, $c_inodes, $blk_size, $blks,
    $ublks, $inds, $uinds, $tmp_k, $tmp_inodes, $cnt
  );

  ($image, $dir, $fs, $c_k, $c_inodes, $x_k, $x_inodes) = @_;

  $cnt = 1;

  SUSystem "umount /mnt 2>/dev/null";

  while($cnt <= 2) {
#    print ">>$c_k, $c_inodes\n";
    ( $tmp_k, $blk_size, $tmp_inodes ) = $fs eq 'minix' ? MakeMinixImage($image, $c_k, $c_inodes) : MakeExt2Image($image, $c_k, $c_inodes);

    die "$Script: failed to create a $fs fs on \"$image\"" unless $tmp_inodes;

    printf "$Script: created ${cnt}. image \"%s\": %u kbyte, %u inodes\n", $image, $tmp_k, $tmp_inodes;

    SUSystem "mount -oloop $image /mnt" and die "$Script: mount failed";

    # copy everything
    SUSystem "sh -c 'tar -C $dir -cf - . | tar -C /mnt -xpf -'" and
      die "$Script: could not add all files to the image";

    # check the current disk usage
    for ( `df -Pk /mnt` ) {
      ($blks, $ublks) = ($1, $2) if /^\S+\s+(\d+)\s+(\d+)/;
    }

    for ( `df -Pki /mnt` ) {
      ($inds, $uinds) = ($1, $2) if /^\S+\s+(\d+)\s+(\d+)/;
    }

    # unmount it
    SUSystem "umount /mnt" and die "$Script: umount failed";

#    print "$Script: $image: ${ublks}k/${blks}k used ($uinds/$inds inodes)\n";

    $c_k += $x_k - ($blks - $ublks);
    $c_inodes += $x_inodes - ($inds - $uinds);

    $cnt++;
  }

  print "$Script: $image: ${ublks}k/${blks}k used ($uinds/$inds inodes)\n";
}

1;
