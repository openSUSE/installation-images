#! /usr/bin/perl

use strict;
use File::Temp;
use Test::More;

use vars '$Script';
my $Script = "test";

use MakeExt2Image;

my $tmp_file = File::Temp->new(TEMPLATE => "/tmp/test.XXXXXXXX");

# image list
my $todo = [
  { size => "2000", inodes => "200" },
  { size => "5000", inodes => undef },
];

for my $task (@$todo) {
  note("creating ext2 fs: size = $task->{size}, inodes = $task->{inodes}");

  my @res = MakeExt2Image "$tmp_file", $task->{size}, $task->{inodes};

  # fs size must match
  is((-s $tmp_file)/1024, $task->{size}, "size correct");

  # free blocks are just an approximation
  cmp_ok($res[0], ">=", $task->{size} * 0.95, "free space not too small");
  cmp_ok($res[0], "<=", $task->{size}, "free space not too big");

  # always 1 kb
  is($res[1], 1024, "block size correct");

  # inode count should be exact
  is($res[2], $task->{inodes}, "inodes correct") if $task->{inodes};
}

done_testing();
