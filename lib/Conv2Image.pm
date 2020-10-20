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
use File::Temp;

sub Conv2Image
{
  my (
    $image, $dir, $fs, $x_k, $x_inodes, $c_k, $c_inodes, $blk_size, $blks,
    $ublks, $inds, $uinds, $tmp_k, $tmp_inodes, $cnt, $size, $name, $mkcramfs,
    $mksquashfs
  );

  ($image, $dir, $fs, $c_k, $c_inodes, $x_k, $x_inodes) = @_;

  die "Error: you must be root to build images\n" if $>;

  $cnt = 1;

  if($fs eq 'cramfs') {
    $mkcramfs = "/usr/bin/mkcramfs" if -x "/usr/bin/mkcramfs";
    $mkcramfs = "/sbin/mkfs.cramfs" if -x "/sbin/mkfs.cramfs";
    die "$Script: no mkfs.cramfs\n" unless $mkcramfs;
    system "rm -f $image";
    system "touch $image $image.log";	# just to ensure the image gets the correct owner
    system "sh -c '$mkcramfs $dir $image >$image.log'" and die "$Script: mkfs.cramfs failed";
    $size = -s $image;
    die "$Script: no image?" if $size == 0;
    $name = $image;
    $name =~ s#^.*/##;
    die "$Script: strange image name" if $name eq "";
    return;
  }
  if($fs eq 'squashfs') {
    $mksquashfs = "/usr/bin/mksquashfs" if -x "/usr/bin/mksquashfs";
    $mksquashfs = "/usr/bin/mksquashfs4" if -x "/usr/bin/mksquashfs4";
    die "$Script: no mksquashfs\n" unless $mksquashfs;
    system "rm -f $image";
    system "touch $image $image.log";	# just to ensure the image gets the correct owner
    system "sh -c '$mksquashfs $dir $image -comp xz -noappend -no-progress >$image.log'" and die "$Script: mksquashfs failed";
    $size = -s $image;
    die "$Script: no image?" if $size == 0;
    return;
  }
  elsif($fs eq 'cpio') {
    system "rm -f $image";
    system "touch $image";	# just to ensure the image gets the correct owner
    system "sh -c '( cd $dir ; find . | cpio --quiet -o -H newc ) >$image'" and die "$Script: cpio failed";
    return;
  }
  elsif($fs ne 'ext2') {
    die "ERRROR: no support for \"$fs\"!\n"
  }

  while($cnt <= 2) {
#    print ">>$c_k, $c_inodes\n";
    ( $tmp_k, $blk_size, $tmp_inodes ) = MakeExt2Image($image, $c_k, $c_inodes);

    die "$Script: failed to create a $fs fs on \"$image\"" unless $tmp_inodes;

    print STDERR "$Script: Warning: inode number much smaller than expected ($tmp_inodes < $c_inodes)!\n" if $tmp_inodes < $c_inodes - 100;

#    printf "$Script: created ${cnt}. image \"%s\": %u kbyte, %u inodes\n", $image, $tmp_k, $tmp_inodes;
    if($cnt == 2) {
      printf "$Script: created \"%s\": %u kbyte, %u inodes\n", $image, $tmp_k, $tmp_inodes;
    }

    my $tmp_dir = File::Temp->newdir(TEMPLATE => "/tmp/Conv2Image.XXXXXXXX");

    system "mount -oloop $image $tmp_dir" and die "$Script: mount failed";

    # copy everything
    if(system "sh -c 'tar --sparse -C $dir -cf - . | tar -C $tmp_dir -xpf -'") {
      system "umount $tmp_dir" and warn "$Script: umount failed";
      die "$Script: could not add all files to image";
    }

    # check the current disk usage
    for ( `df -Pk $tmp_dir 2>/dev/null` ) {
      ($blks, $ublks) = ($1, $2) if /^\S+\s+(\d+)\s+(\d+)/;
    }

    for ( `df -Pki $tmp_dir 2>/dev/null` ) {
      ($inds, $uinds) = ($1, $2) if /^\S+\s+(\d+)\s+(\d+)/;
    }

    # unmount it
    system "umount $tmp_dir" and die "$Script: umount failed";

#    print "$Script: $image: ${ublks}k/${blks}k used ($uinds/$inds inodes)\n";

    $c_k += $x_k - ($blks - $ublks);
    $c_inodes += $x_inodes - ($inds - $uinds);

    $cnt++;
  }

  print "$Script: $image: ${ublks}k/${blks}k used ($uinds/$inds inodes)\n";
}

1;
