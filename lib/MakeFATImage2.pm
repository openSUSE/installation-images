#! /usr/bin/perl

require Exporter;
@ISA = qw ( Exporter );
@EXPORT = qw ( MakeFATImage2 );

use FAT;
use strict 'vars';
use integer;

# - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - -

my $boot_file = "${BasePath}src/mboot/boot";

my $boot_msg = "\r
I'm $ConfigData{product_name} Boot Disk <disk>. I cannot boot. :-(\r
\r
Please try Boot Disk 1.\r\n";


# Not more than 1024 chars (1 cluster)! --> Or adjust cluster size!
my $readme =
"This is $ConfigData{product_name} Boot Disk <disk>.

<x_readme>
To access Boot Disk data, you have to join the individual disk images first:

  cd /where_CD1_is_mounted/boot
  cat bootdsk? >/tmp/bootdisk

Then mount it as usual:

  mount -oloop /tmp/bootdisk /mnt

When you're done, unmount it:

  umount /mnt

If you have changed Boot Disk data and want to get separate Boot Disk images
of floppy size back, split it:

  split -a 1 -b 1440k /tmp/bootdisk /tmp/bootdsk

The new Boot Disks are /tmp/bootdsk[a-<last_disk_letter>].\n";


my $x_readme =
"\n***  There is nothing for you to change on this disk.  ***\n";


# - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - -

# cluster size, extra root dir sectors
my @format = (
  [ 4, 0 ],	# 0 (default)
  undef,	# 1
  [ 4, 1 ],	# 2
  [ 4, 3 ],	# 3
  [ 4, 1 ],	# 4
  [ 4, 3 ],	# 5
  [ 4, 1 ],	# 6
  [ 4, 2 ],	# 7
);

my $opt_disks = 2;
my ($serial, $fat);


sub set_boot_msg
{
  my $msg = shift;
  my $buf;

  open F1, $boot_file;
  read F1, $buf, -s($boot_file);
  close F1;

  $fat->boot_code($buf . $msg . "\x00");
}


# - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - -

sub create_image
{
  my ($cl_size, $x_root, $i, $ldsk);

  $cl_size = $format[$opt_disks] ? $format[$opt_disks][0] : $format[0][0];
  $x_root = $format[$opt_disks] ? $format[$opt_disks][1] : $format[0][1];

  $fat = FAT::new;

  $fat->resize_image(1440 * 1024 * $opt_disks);

  $fat->sector_size(0x200);
  $fat->res_sectors(1);
  $fat->extended_bpb(0x29);

  $fat->sectors(1440 * 2 * $opt_disks);
  $fat->track_size(18);
  $fat->heads(2);
  $fat->cluster_size($cl_size);
  $fat->fats(1);
  $fat->root_entries((16 * $x_root) + 1);

  $fat->media_id(0xf0);
  $fat->drive_id(0x00);

  $fat->serial($serial + 0);
  $fat->volume_id("BOOTDISK1");
  $fat->manuf_id("SUSE");

  $fat->fs_date(time);
  $fat->fs_time(0, 10, 9);

  $fat->init_fs;

  $i = $readme;
  $i =~ s/<x_readme>//g;
  $i =~ s/<disk>/1/g;
  $ldsk = chr($opt_disks - 1 + ord('a'));
  $i =~ s/<last_disk_letter>/$ldsk/g;
  $fat->add_file(0, 1, "README  TXT", 0, $i);
}


sub create_small_image
{
  my $disk = shift;
  my ($max_cl, $i, $dsk, $ldsk);

  $fat->offset($disk * 1440 * 1024);

  $fat->sector_size(0x200);
  $fat->res_sectors(1);
  $fat->extended_bpb(0x29);

  $fat->sectors(1440 * 2);
  $fat->track_size(18);
  $fat->heads(2);
  $fat->cluster_size(2);
  $fat->fats(1);
  $fat->root_entries((16 * 1) + 1);

  $fat->media_id(0xf0);
  $fat->drive_id(0x00);

  $fat->serial($serial + ($disk & 0xf));

  $dsk = $disk + 1;

  $fat->volume_id("BOOTDISK$dsk");
  $fat->manuf_id("SUSE");

  $i = $boot_msg;
  $i =~ s/<disk>/$dsk/g;
  set_boot_msg($i);

  $fat->init_fs;

  $i = $readme;
  $i =~ s/<x_readme>/$x_readme/g;
  $i =~ s/<disk>/$dsk/g;
  $ldsk = chr($opt_disks - 1 + ord('a'));
  $i =~ s/<last_disk_letter>/$ldsk/g;
  $fat->add_file(0, 1, "README  TXT", 0, $i);

  $max_cl = $fat->clusters + 2;

  for($i = 3; $i < $max_cl; $i++) {
    $fat->fat_entry($i, 0xfff7);
  }

  # printf "res = %u\n", $fat->cluster_to_sector(2);

  if($i = $fat->wasted_sectors) {
    warn "small image: $i sectors wasted\n"
  }
}


sub MakeFATImage2
{
  my ($i, $res_sectors, $start_sec, $sec, $cl, $clusters, $free_clusters);
  my ($fat_entry, $file, $verbose);

  ($file, $opt_disks, $verbose) = @_;

  $serial = int(rand(0x10000000)) << 4;

  create_image;

  for($i = 1; $i < $opt_disks; $i++) {
    create_small_image $i;
  }

  $res_sectors = $fat->cluster_to_sector(2 + 1);	# 1 cluster for 'README'

  # print "res_sectors = $res_sectors\n";

  $fat->offset(0);

  for($i = 1; $i < $opt_disks; $i++) {
    $start_sec = 1440 * 2 * $i;
    for($sec = $start_sec; $sec < $start_sec + $res_sectors; $sec ++) {
      $cl = $fat->sector_to_cluster($sec);
      $fat->fat_entry($cl, 0xfff7);
      # print "sec = $sec, $cl\n";
    }
  }

  $clusters = $fat->clusters + 2;
  $free_clusters = 0;

  for($i = 2; $i < $clusters; $i++) {
    $fat_entry = $fat->fat_entry($i);
    $free_clusters++ if defined($fat_entry) && $fat_entry == 0;
  }

  if($verbose) {
    printf "      image size = %u\n", $fat->sectors * $fat->sector_size;
    printf "        manuf id = \"%s\"\n", $fat->manuf_id;
    printf "     sector size = 0x%x\n", $fat->sector_size;
    printf " sectors/cluster = %u\n", $fat->cluster_size;
    printf "reserved sectors = %u\n", $fat->res_sectors;
    printf "            fats = %u\n", $fat->fats;
    printf "root dir entries = %u\n", $fat->root_entries;
    printf "         sectors = %u\n", $fat->sectors;
    printf "        media id = 0x%02x\n", $fat->media_id;
    printf "     sectors/fat = %u\n", $fat->fat_size;
    printf "   sectors/track = %u\n", $fat->track_size;
    printf "           heads = %u\n", $fat->heads;
    printf "  hidden sectors = %u\n", $fat->hidden_sectors;
    printf "        drive id = 0x%02x\n", $fat->drive_id;
    printf " extended bpb id = 0x%02x\n", $fat->extended_bpb;
    printf "          serial = 0x%08x\n", $fat->serial;
    printf "       volume id = \"%s\"\n", $fat->volume_id;
    printf "        fat bits = %u\n", $fat->fat_bits;
    printf "        clusters = %u\n", $fat->clusters;
    printf "   free clusters = %u (%uk)\n", $free_clusters, ($free_clusters * $fat->cluster_size * $fat->sector_size) >> 10;
    printf "  wasted sectors = %u\n", $fat->wasted_sectors if $fat->wasted_sectors;
  }

  $fat->write_image($file) if $file;

  return ( $free_clusters, $fat->cluster_size * $fat->sector_size );
}


1;
