#! /usr/bin/perl

# Write an empty floppy image.
#
# Unfortunately, mformat does not allow writing a floppy with only one FAT
# (instead of 2). This way we save a few kbytes (11 to be exact).
#
# Usage:
#
#   use MakeFATImage;
#
#   exported functions:
#     MakeFATImage(file_name, label, cluster_size);
#
#   Note: the label can contain only up to 11 chars.


=head1 MakeFATImage

C<MakeFATImage.pm> is a perl module that can be used to create FAT file
systems. It exports the following symbols:

=over

=item *

C<MakeFATImage(file_name, label, cluster_size, sec_p_track)>

=back

=head2 Usage

use MakeFATImage;

=head2 Description

=over

=item *

C<MakeFATImage(file_name, label, cluster_size, sec_p_track)>

C<MakeFATImage> creates an empty DOS FAT file system image in C<file_name>. 
The C<label> must not exceed 11 chars. C<cluster_size> is given in numbers
of sectors per cluster (typically 1 for floppy disks).

The file system created will have only 1 FAT (usually there are 2) and only a minimum
number of root directory entries. This way we save 11 kbytes on a 1.44M floppy.

Note: you I<can> specify such things as a C<cluster_size> of 5 sectors/cluster. Linux
won't choke on it. But I don't know how Win/Dos will like it.

B<Return Values>

C<MakeFATImage> returns a list with 2 elements:

C<(blocks, block_size)>

=over

=item *

C<blocks> is the number of blocks that can be used on that file system

=item *

C<block_size> is the size of a block in bytes

=back

So, C<blocks * block_size> gives the usable file system size in bytes.

On any failure, C<( )> is returned.

=back

=cut


require Exporter;
@ISA = qw ( Exporter );
@EXPORT = qw ( MakeFATImage );

use strict 'vars';
use integer;


# DOSDate(day, month, year)
# or
# DOSDate(unix_time)

sub DOSDate
{
  my (@u);

  @u = @_;
  if(@u == 1) {
    @u = (localtime shift)[3..5];
    $u[1]++;
  }

  return $u[0] + ($u[1] << 5) + (($u[2] < 80 ? 0 : $u[2] - 80) << 9);
}


# DOSTime(second, minute, hour)
# or
# DOSTime(unix_time)

sub DOSTime
{
  my (@u);

  @u = @_;
  if(@u == 1) {
    @u = (localtime shift)[0..2];
  }

  return ($u[0] >> 1) + ($u[1] << 5) + ($u[2] << 11);
}


sub MakeFATImage
{
  my (
    $file_name, $id8, $id11, $heads, $tracks, $fats, $root_ents,
    $drive_id, $fatbits, $secs_p_cluster, $sec_size, $hidden_secs,
    $drive_number, $serial_id, $sectors, $fatsecs, $usable_secs,
    $clusters, $rootsecs, $sec_p_track, $bs, $fs, $rs, $zs, $i, $j, @i
  );

  ( $file_name, $id11, $secs_p_cluster, $sec_p_track, $heads, $tracks ) = @_;

  # if $heads and $tracks are specified, assume a disk image, otherwise
  # we'll make a floppy image

  if(length($id11) > 11) {
    print STDERR "$Script: WARNING: volume label \"$id11\" too long\n";
    return ( undef, undef )
  }

  $id8 = "SUSE";		# will be overwritten by syslinux anyway
  $drive_id = $tracks ? 0xf8 : 0xf0;	# 0xf0: floppy; 0xf8: hard disk
  $fats = $tracks ? 2 : 1;
  $sec_p_track = 18 unless $sec_p_track;
  $heads = 2 unless $heads;
  $tracks = 80 unless $tracks;
  $root_ents = 16;
  $sec_size = 0x200;
  $serial_id = 0x31415926;

  $hidden_secs = 0;

  $drive_number = $drive_id == 0xf8 ? 0x80 : 0x00;

  $sectors = $sec_p_track * $heads * $tracks;

  $clusters = $sectors / $secs_p_cluster;	# first approx

  $fatbits = $clusters <= 0xff5 ? 12 : 16;	# see if 12 bit FAT would be ok

  $fatsecs = (($fatbits * ($clusters + 2) + 7) / 8 + $sec_size - 1) / $sec_size;

  $rootsecs = ($root_ents * 0x20 + $sec_size - 1) / $sec_size;

  $usable_secs = $sectors - $fats * $fatsecs - $rootsecs - 1;
  $clusters = $usable_secs / $secs_p_cluster;

  $rootsecs += $usable_secs % $secs_p_cluster;	# don't waste space for nothing
  $root_ents = $rootsecs * $sec_size / 0x20;

  # the boot sector
  $bs = pack (
    "C3A8vCvCvvCvvvVVCCCVA11A8Z448v",

    0xeb, 0xfe, 0x90,		# jmp $; nop
    $id8,			# some label
    $sec_size,			# sector length (e.g. 512 bytes)
    $secs_p_cluster,		# sector per cluster (e.g. 1)
    0x1,			# 1 reserved sector (the boot sector)
    $fats,			# fats (typically 1 or 2)
    $root_ents,			# root dir entries (multiple of 16)
    $sectors >> 16 ? 0 : $sectors,	# total size in sectors for < 32MB
    $drive_id,			# drive id
    $fatsecs,			# sectors per fat
    $sec_p_track,		# sectors per track
    $heads,			# heads
    $hidden_secs,		# hidden sectors (aka start sector of this partition)
    $sectors >> 16 ? $sectors : 0,	# total size in sectors for >= 32MB
    $drive_number,		# drive number (0x00: floppy, 0x80: hard disk)
    0,				# reserved
    0x29,			# extended BPB id
    $serial_id,			# serial number
    $id11,			# volume label
    $fatbits == 12 ? "FAT12" : "FAT16",	# fat id
    "",				# fill up with zeroes
    0xaa55			# some id
  );

  # the first fat sector
  # ##### needs to be generalized!!!
  $fs = $fatbits == 12 ?
    pack( "C3Z509", $drive_id, 0xff, 0xff, "" ) :
    pack( "C3Z508", $drive_id, 0xff, 0xff, 0xff, "" );

  # the first root directory sector (add volume label)

  @i = (time);
  if(defined %ConfigData) {
    @i = (0 , @ConfigData{'suse_minor_release', 'suse_major_release'});
    $i[1] *= 10;
  }

  $rs = pack (
    "A11CZ10vvZ486",

    $id11,			# volume label
    0x08,			# attribute for volume label
    "",				# fill with zeroes
    DOSTime(@i),		# time
    DOSDate(time),		# date
    ""
  );

  # sector with zeroes
  $zs = pack ( "Z512", "" );

  # ok, write out the image
  open F, ">$file_name" or return ( undef, undef );

  # boot sector
  print F $bs;

  # fat sectors
  for($i = 0; $i < $fats; $i++) {
    for($j = 0; $j < $fatsecs; $j++) {
      print F $j ? $zs : $fs;
    }
  }

  # root directory and data sectors
  for($i = 0; $i < $sectors - $fats * $fatsecs - 1; $i++) {
    print F $i ? $zs : ($drive_number == 0x00 ? $rs : $zs);
  }

  # we're done!
  close F;

  return ( $clusters, $sec_size * $secs_p_cluster )
}


1;
