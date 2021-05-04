#! /usr/bin/perl

use strict;
use File::Temp;
use File::Basename;
use Test::More;

use ResolveDepsLibsolv;

$ResolveDepsLibsolv::Script = "test";

sub fixture {
    my $filename = shift;
    my $dirname = dirname(__FILE__);
    return "$dirname/data/$filename";
}

is_deeply(
    resolve_deps_libsolv([], [], fixture "empty.solv"),
    {},
    "resolve an empty request"
);

is_deeply(
    resolve_deps_libsolv(["bash"], [], fixture "bash-nodeps.solv"),
    {},
    "a missing dependency is not returned"
);

# package_name => pulled in by package_name
my $bash_deps = {
    "filesystem" => "glibc",
    "glibc" => "bash",
    "libgcc_s1" => "libncurses6",
    "libncurses6" => "libreadline8",
    "libreadline8" => "bash",
    "libstdc++6" => "libncurses6",
    "system-user-root" => "filesystem",
    "terminfo-base" => "libncurses6",
    "update-alternatives" => "bash",
};

is_deeply(
    resolve_deps_libsolv(["bash"], [], fixture "bash-deps.solv"),
    $bash_deps,
    "resolve a bash request in a small solv"
);

my $partial_bash_deps = {
    "filesystem" => "glibc",
    "glibc" => "bash",
    "system-user-root" => "filesystem",
    "update-alternatives" => "bash",
};

is_deeply(
    resolve_deps_libsolv(["bash"], ["libreadline8"], fixture "bash-deps.solv"),
    $partial_bash_deps,
    "resolve a bash request in a small solv, ignoring readline"
);

done_testing();
