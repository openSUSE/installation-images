#! /usr/bin/perl

use strict;
use File::Temp;
use Test::More;

my $tmp_dir = File::Temp->newdir(TEMPLATE => "/tmp/test.XXXXXXXX");

# setup test data
system "mkdir -p $tmp_dir/{a,b}; touch $tmp_dir/{a,b}/0";

note("check for dash bug bsc#1177691");

# bsc#1177691
#
# dash does not expand file name globs correctly if the last path component
# of the glob is not a pattern
#
# e.g. "*/bar" fails while "*/b[a]r" works
#

my $dash_output = `cd $tmp_dir; dash -c 'echo -n */0'`;

is($dash_output, "a/0 b/0", "dash file name expansion");

done_testing();
