#! /usr/bin/perl

use strict;
use File::Temp;
use Test::More;

use vars '$Script';
my $Script = "test";

use CompressImage;

my $tmp_file = File::Temp->new();

# supported image types
my $todo = [
  { name => "gzip",    arg => "gzip", match_name => "gzip", match => qr/gzip/ },
  { name => "xz",      arg => "xz",   match_name => "xz",   match => qr/XZ/   },
  { name => "default", arg => undef,  match_name => "gzip", match => qr/gzip/ },
];

for my $task (@$todo) {
  note("checking $task->{name} compression");

  system "echo foo > $tmp_file";
  my $size = CompressImage "$tmp_file", $task->{arg};
  my $type = `file $tmp_file`;

  cmp_ok($size, ">", 0, "image created");
  like($type, $task->{match}, "is $task->{match_name} compressed");
}

done_testing();
