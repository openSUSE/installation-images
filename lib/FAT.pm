#! /usr/bin/perl

package FAT;

use strict 'vars';
use integer;


sub new
{
  my $self = {};

  bless $self;

  $self->{offset} = 0;
  $self->{image} = "\x00" x 0x200;

  return $self
}

sub image
{
  my $self = shift;

  return $self->{image};
}


sub offset
{
  my $self = shift;

  $self->{offset} = shift if @_;

  return $self->{offset};
}


sub write_image
{
  my $self = shift;

  if(@_) {
    my $file = shift;
    open W1, ">$file";
    print W1 $self->image;
    close W1;
  }
}


sub read_image
{
  my $self = shift;

  if(@_) {
    my $file = shift;
    my $image;
    open F1, $file;
    read F1, $image, -s($file);
    close F1;
    $self->{image} = $image;
  }
}


sub resize_image
{
  my $self = shift;
  my $new_size = shift;

  my $len = $new_size + $self->{offset} - length($self->image);
  $self->{image} .= "\x00" x $len if $len > 0;
}


sub _string
{
  my $self = shift;
  my $ofs = $self->{offset} + shift;
  my $len = 0 + shift;

  substr($self->{image}, $ofs, $len) = pack("a$len", shift) if @_[0];
  return substr($self->{image}, $ofs, $len);
}


sub _byte
{
  my $self = shift;
  my $ofs = $self->{offset} + shift;

  substr($self->{image}, $ofs, 1) = pack("C", shift) if @_[0];
  return unpack("C", substr($self->{image}, $ofs, 1));
}


sub _word
{
  my $self = shift;
  my $ofs = $self->{offset} + shift;

  substr($self->{image}, $ofs, 2) = pack("v", shift) if @_[0];
  return unpack("v", substr($self->{image}, $ofs, 2));
}


sub _dword
{
  my $self = shift;
  my $ofs = $self->{offset} + shift;

  substr($self->{image}, $ofs, 4) = pack("V", shift) if @_[0];
  return unpack("V", substr($self->{image}, $ofs, 4));
}


sub sector
{
  my $self = shift;
  my $sec = shift;
  my $len = $self->sector_size;
  my $ofs = $sec * $len + $self->{offset};

  if(@_) {
    my $buf = shift;
    my $xlen = $len - length($buf);
    $buf .= "\x00" x $xlen if $xlen > 0;
    substr($self->{image}, $ofs, $len) = $buf;
  }

  return substr($self->{image}, $ofs, $len);
}


sub cluster
{
  my $self = shift;
  my $cl_nr = shift;
  my $len = $self->sector_size * $self->cluster_size;

  return undef if $cl_nr < 2;

  my $ofs = ($cl_nr - 2) * $len + $self->{offset};

  $ofs += ($self->res_sectors + $self->fats * $self->fat_size + $self->_root_sectors) * $self->sector_size;

  if(@_) {
    my $buf = shift;
    my $xlen = $len - length($buf);
    $buf .= "\x00" x $xlen if $xlen > 0;
    substr($self->{image}, $ofs, $len) = $buf;
  }

  return substr($self->{image}, $ofs, $len);
}


#
# dir_entry(cluster, entry_index [, buffer])
#
sub dir_entry
{
  my $self = shift;
  my $cl_nr = shift;
  my $entry = shift;
  my $len = 32;
  my $ofs;

  return undef if $cl_nr < 2 && $cl_nr != 0;

  $ofs = $self->res_sectors + $self->fats * $self->fat_size;
  if($cl_nr >= 2) {
    $ofs += $self->_root_sectors + ($cl_nr - 2) * $self->cluster_size;
  }

  $ofs = $ofs * $self->sector_size + $self->{offset} + ($entry << 5);

  if(@_) {
    my $buf = shift;
    my $xlen = $len - length($buf);
    $buf .= "\x00" x $xlen if $xlen > 0;
    substr($self->{image}, $ofs, $len) = $buf;
  }

  return substr($self->{image}, $ofs, $len);
}


# dos_date(day, month, year)
# or
# dos_date(unix_time)

sub dos_date
{
  my (@u);

  @u = @_;
  if(@u == 1) {
    @u = (localtime shift)[3..5];
    $u[1]++;
  }

  return pack("v", $u[0] + ($u[1] << 5) + (($u[2] < 80 ? 0 : $u[2] - 80) << 9));
}


# dos_time(second, minute, hour)
# or
# dos_time(unix_time)

sub dos_time
{
  my (@u);

  @u = @_;
  if(@u == 1) {
    @u = (localtime shift)[0..2];
  }

  return pack("v", ($u[0] >> 1) + ($u[1] << 5) + ($u[2] << 11));
}


sub fs_date
{
  my $self = shift;

  $self->{fs_date} = dos_date(@_) if @_;

  return $self->{fs_date};
}


sub fs_time
{
  my $self = shift;

  $self->{fs_time} = dos_time(@_) if @_;

  return $self->{fs_time};
}


#
# dir_entry(name, attribute, time, date, start, size);
#
sub new_dir_entry
{
  my ($name, $attribute, $time, $date, $start, $size) = @_;

  return pack("A11CZ10a2a2vV", $name, $attribute, "", $time, $date, $start, $size);
}


# - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - -
sub boot_code
{
  my $self = shift;

  $self->_word(0, 0xfeeb);
  $self->_byte(2, 0x90);

  if(@_) {
    my $code = shift;
    $self->_byte(1, 0x3c);
    $self->_string(0x3e, length($code), $code);
  }
}


sub manuf_id
{
  my $self = shift;

  if(@_) {
    return unpack("A8", $self->_string(0x03, 8, pack("A8", shift)));
  }
  else {
    return unpack("A8", $self->_string(0x03, 8));
  }
}


sub sector_size
{
  my $self = shift;

  return $self->_word(0x0b, shift);
}


sub cluster_size
{
  my $self = shift;

  return $self->_byte(0x0d, shift);
}


sub res_sectors
{
  my $self = shift;

  return $self->_word(0x0e, shift);
}


sub fats
{
  my $self = shift;

  return $self->_byte(0x10, shift);
}


sub root_entries
{
  my $self = shift;

  if(@_) {
    my $entries = shift;
    my $sec_size = $self->sector_size;
    if($sec_size) {
      $entries = (((($entries << 5) + $sec_size - 1) / $sec_size) * $sec_size) >> 5;
    }
    return $self->_word(0x11, $entries);
  }
  else {
    return $self->_word(0x11, shift);
  }
}


sub sectors
{
  my $self = shift;
  my $secs;

  if(@_) {
    $secs = shift;
    if($secs >> 16) {
      $self->_dword(0x20, $secs);
    }
    else {
      $self->_word(0x13, $secs);
    }
  }

  $secs = $self->_word(0x13);
  $secs = $self->_dword(0x20) unless $secs;

  return $secs;
}


sub media_id
{
  my $self = shift;

  return $self->_byte(0x15, shift);
}


sub fat_size
{
  my $self = shift;

  return $self->_word(0x16, shift);
}


sub track_size
{
  my $self = shift;

  return $self->_word(0x18, shift);
}


sub heads
{
  my $self = shift;

  return $self->_word(0x1a, shift);
}


sub hidden_sectors
{
  my $self = shift;

  return $self->_dword(0x1c, shift);
}


sub drive_id
{
  my $self = shift;

  return $self->_byte(0x24, shift);
}


sub extended_bpb
{
  my $self = shift;

  return $self->_byte(0x26, shift);
}


sub serial
{
  my $self = shift;

  return $self->_dword(0x27, shift);
}


sub volume_id
{
  my $self = shift;

  if(@_) {
    return unpack("A11", $self->_string(0x2b, 11, pack("A11", shift)));
  }
  else {
    return unpack("A11", $self->_string(0x2b, 11));
  }
}


sub fat_bits
{
  my $self = shift;

  if(@_) {
    my $bits = shift;
    $bits = 16 unless $bits == 12 || $bits == 32;
    $self->_string(0x36, 8, sprintf("FAT%-5u", $bits));
  }

  my $id = $self->_string(0x36, 8);
  if($id =~ /FAT(\d+)/) {
    $id = $1 + 0;
  }
  else {
    $id = undef;
  }

  return $id;
}


sub _root_sectors
{
  my $self = shift;

  return (($self->root_entries << 5) + $self->sector_size - 1) / $self->sector_size;
}


sub _data_sectors
{
  my $self = shift;

  return $self->sectors - $self->res_sectors - $self->fats * $self->fat_size - $self->_root_sectors;
}


sub clusters
{
  my $self = shift;

  return $self->_data_sectors / $self->cluster_size;
}


sub cluster_to_sector
{
  my $self = shift;
  my $cl_nr = shift;

  return undef if $cl_nr < 2;

  return $self->res_sectors + $self->fats * $self->fat_size + $self->_root_sectors +
    ($cl_nr - 2) * $self->cluster_size;
}


sub sector_to_cluster
{
  my $self = shift;
  my $sec_nr = shift;

  $sec_nr -= $self->res_sectors + $self->fats * $self->fat_size + $self->_root_sectors;

  return undef if $sec_nr < 0;

  return $sec_nr / $self->cluster_size + 2;
}


sub wasted_sectors
{
  my $self = shift;

  return $self->_data_sectors - $self->clusters * $self->cluster_size;
}


sub fat_entry
{
  my $self = shift;
  my $cl_nr = shift;
  my $bits = $self->fat_bits;
  my $fats = $self->fats;
  my ($cl, $i, $ofs);

  return undef unless $bits;

  if(@_) {
    for($i = 0; $i < $fats; $i++) {
      if($bits == 12) {
        $ofs = ($self->res_sectors + $self->fat_size * $i) * $self->sector_size + $cl_nr + ($cl_nr >> 1);
        $cl = $self->_word($ofs);
        if($cl_nr & 1) {
          $cl = ($cl & ~0xfff0) + (($_[0] << 4) & 0xfff0);
        }
        else {
          $cl = ($cl & ~0xfff) + ($_[0] & 0xfff);
        }
        $self->_word($ofs, $cl);
      }
      elsif($bits == 16) {
        $self->_word(($self->res_sectors + $self->fat_size * $i) * $self->sector_size + ($cl_nr << 1), $_[0]);
      }
    }
  }

  if($bits == 12) {
    $cl = $self->_word($self->res_sectors * $self->sector_size + $cl_nr + ($cl_nr >> 1));
    if($cl_nr & 1) {
      $cl >>= 4;
    }
    else {
      $cl &= 0xfff;
    }
  }
  elsif($bits == 16) {
    $cl = $self->_word($self->res_sectors * $self->sector_size + ($cl_nr << 1));
  }

  return $cl;
}


sub free_cluster
{
  my $self = shift;
  my $clusters = $self->clusters + 2;
  my $cl_nr;

  for($cl_nr = 2; $cl_nr < $clusters; $cl_nr ++) {
    return $cl_nr unless $self->fat_entry($cl_nr);
  }

  return undef;
}


sub add_file
{
  my $self = shift;
  my ($cl_nr, $idx, $name, $attr, $buf) = @_;
  my $cl_len = $self->cluster_size * $self->sector_size;
  my $len = length($buf);
  my ($i, $cl, $start, $next);

  if($len) {
    $start = $self->free_cluster;
    return undef unless $start;
  }

  $self->dir_entry($cl_nr, $idx, new_dir_entry(
    $name, $attr, $self->fs_time, $self->fs_date, $start, $len
  ));

  return 1 unless $len;

  for($i = 0; $i < $len; $i += $cl_len) {
    $self->cluster($start, substr($buf, $i, $cl_len));
    $self->fat_entry($start, 0xffff);
    if($i + $cl_len < $len) {
      $next = $self->free_cluster;
      return undef unless $next;
      $self->fat_entry($start, $next);
    }
    $start = $next;
  }

  return 1;
}


sub add_dir
{
  my $self = shift;
  my ($cl_nr, $idx, $name, $attr) = @_;
  my $start = $self->free_cluster;

  return undef unless $start;

  $self->dir_entry($cl_nr, $idx, new_dir_entry(
    $name, 0x10 | $attr, $self->fs_time, $self->fs_date, $start, 0
  ));
  $self->fat_entry($start, 0xffff);

  $self->dir_entry($start, 0, new_dir_entry(
    ".", 0x10 | $attr, $self->fs_time, $self->fs_date, $start, 0
  ));
  $self->dir_entry($start, 1, new_dir_entry(
    "..", 0x10 | $attr, $self->fs_time, $self->fs_date, $cl_nr, 0
  ));

  return $start;
}


sub init_fs
{
  my $self = shift;
  my ($clusters, $i, $ofs, $buf);

  $self->_word($self->sector_size - 2, 0xaa55);
  $self->resize_image($self->sector_size * $self->sectors);

  $clusters = $self->clusters;

  if(!$self->fat_bits && !$self->fat_size) {
    for(my $i = 0; $i < 2; $i++) {
      # two iterations should be enough
      $self->fat_bits($clusters <= 0xff5 ? 12 : 16);
      $self->fat_size((($self->fat_bits * ($clusters + 2) + 7) / 8 + $self->sector_size - 1) / $self->sector_size);
      $clusters = $self->clusters;
    }
  }

  for($i = $self->res_sectors; $i < $self->sectors; $i++) {
    # clear all sectors
    $self->sector($i, undef);
  }

  for($i = 0; $i < $self->fats; $i++) {
    $ofs = ($self->res_sectors + $i * $self->fat_size) * $self->sector_size;
    $self->_byte($ofs, $self->media_id);
    $self->_word($ofs + 1, 0xffff);
    $self->_byte($ofs + 3, 0xff) if $self->fat_bits >= 16;
    $self->_dword($ofs + 4, 0xffffffff) if $self->fat_bits == 32;
  }

  $self->add_file(0, 0, $self->volume_id, 8, undef);
}


1;
