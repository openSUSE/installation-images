#! /usr/bin/perl

use strict;
use File::Temp;
use Test::More;

use vars '$Script';
$Script = "test";

use MakeExt2Image;
use Conv2Image;

die("you must be root to run this test") if $>;

my $tmp_dir = File::Temp->newdir(TEMPLATE => "/tmp/test.XXXXXXXX");
my $tmp_file = File::Temp->new(TEMPLATE => "/tmp/test.XXXXXXXX");

# additional cleanup
END { unlink "$tmp_file.log" }

# test image dummy content
system "mkdir -p $tmp_dir/{foo,bar}; touch $tmp_dir/{foo,bar}/{0,1,2,3,4}";

# test image size estimates
my $start_size = `du --apparent-size -k -s $tmp_dir 2>/dev/null` + 0;
my $start_inodes = `find $tmp_dir | wc -l 2>/dev/null` + 0;

# leave that much extra space
my $extra_size = 1000;		# kbyte
my $extra_inodes = 200;

# supported image types
my $todo = [
  { name => "squashfs", match => qr/Squashfs/                   },
  { name => "cramfs",   match => qr/Compressed ROM File System/ },
  { name => "cpio",     match => qr/ASCII cpio/                 },
  { name => "ext2",     match => qr/ext2/                       },
];

for my $task (@$todo) {
  note("create $task->{name}");

  Conv2Image "$tmp_file", "$tmp_dir", $task->{name}, $start_size, $start_inodes, $extra_size, $extra_inodes;

  my $size = -s "$tmp_file";
  my $type = `file $tmp_file`;

  cmp_ok($size, ">", 0, "image has been created");
  like($type, $task->{match}, "is $task->{name} image");
}

done_testing();
