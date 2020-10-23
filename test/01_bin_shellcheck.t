#! /usr/bin/perl

use strict;
use Test::More;

note("check shell scripts for pitfalls");

# this should cover at least the scripts using dash
my $todo = [
  { name => "inst_setup",       arg => "data/root/etc/inst_setup data/root/etc/inst_setup_ssh" },
];

for my $task (@$todo) {
  note("checking $task->{name}");
  my $result = `shellcheck $task->{arg}`;
  # log full report to verbose output
  note($result) if $result;
  ok(!$result, "shellcheck $task->{name}");
}

done_testing();
