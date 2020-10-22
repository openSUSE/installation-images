#! /usr/bin/perl

=head1 NAME

Conv2Image -  convert a directory tree into a (file system) image or archive.

=head1 SYNOPSIS

  use Conv2Image;

  # create squashfs image "foo.img" with content from directory "foo"
  Conv2Image("foo.img", "foo", "squashfs");

  # create ext2 image "foo.img" with content from directory "foo"
  #
  # - the initial size estimation is 1000 kbyte, 100 inodes
  # - the final image will have (roughly) 5000 kbyte free space and 400 free inodes
  Conv2Image("foo.img", "foo", "ext2", 1000, 100, 5000, 400);

=head1 DESCRIPTION

This module converts a directory tree into a file system image or an archive.

=head1 INTERFACE

For types "cramfs", "squashfs", and "cpio":

  Conv2Image(image_name, dir, type);

For type "ext2":

  Conv2Image(image_name, dir, type, start_size, start_inodes, extra_size, extra_inodes);

  start_size and extra_size are in kbyte units.

Conv2Image returns on success; if image creation fails, it will call die with a suitable error message.

For ext2 it is necessary to specify an initial size guess. It does not have to be exact but has to be
large enough to hold the directory content. The file system is created in two passes: the first with
the initial size estimate and then a second taking the desired extra space into account. This is done
to accomodate the (unknown) file system meta data size.

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

  # run two passes; the first is to get an approximation of filesystem metadata overhead
  while($cnt <= 2) {
    ( $tmp_k, $blk_size, $tmp_inodes ) = MakeExt2Image($image, $c_k, $c_inodes);

    die "$Script: failed to create a $fs fs on \"$image\"" unless $tmp_inodes;

    print STDERR "$Script: Warning: inode number much smaller than expected ($tmp_inodes < $c_inodes)!\n" if $tmp_inodes < $c_inodes - 100;

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

    $c_k += $x_k - ($blks - $ublks);
    $c_inodes += $x_inodes - ($inds - $uinds);

    $cnt++;
  }

  print "$Script: $image: ${ublks}k/${blks}k used ($uinds/$inds inodes)\n";
}

1;
