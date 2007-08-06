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
    $ublks, $inds, $uinds, $tmp_k, $tmp_inodes, $cnt, $size, $name, $mkcramfs,
    $mksquashfs
  );

  ($image, $dir, $fs, $c_k, $c_inodes, $x_k, $x_inodes) = @_;

  $cnt = 1;

  SUSystem "umount /mnt 2>/dev/null";

  if($fs eq 'cramfs') {
    $mkcramfs = "/usr/bin/mkcramfs" if -x "/usr/bin/mkcramfs";
    $mkcramfs = "/sbin/mkfs.cramfs" if -x "/sbin/mkfs.cramfs";
    die "$Script: no mkfs.cramfs\n" unless $mkcramfs;
    SUSystem "rm -f $image";
    system "touch $image $image.log";	# just to ensure the image gets the correct owner
    SUSystem "sh -c '$mkcramfs $dir $image >$image.log'" and die "$Script: mkfs.cramfs failed";
    $size = -s $image;
    die "$Script: no image?" if $size == 0;
    $name = $image;
    $name =~ s#^.*/##;
    die "$Script: strange image name" if $name eq "";
    $name .= " " . ($size >> 10);
    SUSystem "pcramfs '$name' $image" and die "$Script: pcramfs failed";
    return;
  }
  if($fs eq 'squashfs') {
    $mksquashfs = "/usr/bin/mksquashfs" if -x "/usr/bin/mksquashfs";
    die "$Script: no mksquashfs\n" unless $mksquashfs;
    SUSystem "rm -f $image";
    system "touch $image $image.log";	# just to ensure the image gets the correct owner
    SUSystem "sh -c '$mksquashfs $dir $image -noappend >$image.log'" and die "$Script: mksquashfs failed";
    $size = -s $image;
    die "$Script: no image?" if $size == 0;
    return;
  }
  elsif($fs eq 'cpio') {
    SUSystem "rm -f $image";
    system "touch $image";	# just to ensure the image gets the correct owner
    SUSystem "sh -c '( cd $dir ; find . | cpio --quiet -o -H newc ) >$image'" and die "$Script: cpio failed";
    return;
  }
  elsif($fs ne 'ext2' && $fs ne 'minix') {
    die "ERRROR: no support for \"$fs\"!\n"
  }

  while($cnt <= 2) {
#    print ">>$c_k, $c_inodes\n";
    ( $tmp_k, $blk_size, $tmp_inodes ) = $fs eq 'minix' ? MakeMinixImage($image, $c_k, $c_inodes) : MakeExt2Image($image, $c_k, $c_inodes);

    die "$Script: failed to create a $fs fs on \"$image\"" unless $tmp_inodes;

    print STDERR "$Script: Warning: inode number much smaller than expected ($tmp_inodes < $c_inodes)!\n" if $tmp_inodes < $c_inodes - 100;

#    printf "$Script: created ${cnt}. image \"%s\": %u kbyte, %u inodes\n", $image, $tmp_k, $tmp_inodes;
    if($cnt == 2) {
      printf "$Script: created \"%s\": %u kbyte, %u inodes\n", $image, $tmp_k, $tmp_inodes;
    }

    SUSystem "mount -oloop $image /mnt" and die "$Script: mount failed";

    # copy everything
    if(SUSystem "sh -c 'tar --sparse -C $dir -cf - . | tar -C /mnt -xpf -'") {
      SUSystem "umount /mnt" and warn "$Script: umount failed";
      die "$Script: could not add all files to image";
    }

    # check the current disk usage
    for ( `df -Pk /mnt 2>/dev/null` ) {
      ($blks, $ublks) = ($1, $2) if /^\S+\s+(\d+)\s+(\d+)/;
    }

    for ( `df -Pki /mnt 2>/dev/null` ) {
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
