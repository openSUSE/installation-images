#!/usr/bin/perl -w
#
# vim: set et ts=4 sw=4 ai si:
#
# Work through a set of language subdirectories, find all *.po files and build
# several sets of used codepoints. E.g., a Japanese font does only need the
# codepoints used in subdirectory "ja", but not the ones used in other
# (overlapping because of Unicode Han-Unification) CJK translations like
# "zh_CN", "zh_TW" etc.
#
# The resulting fonts will be handled as a font replacement stack by Qt. 
#
# FIXME : write more here as program matures; also, write better and more
# accurately
#
#
# 2004 Olaf Dabrunz
#

my $debug=1;

use strict;
use File::Find;
use vars qw($opt_d $opt_l);
use Getopt::Std;

binmode STDOUT, ":utf8";

# find all language subdirectories of the form [a-z][a-z](_[A-Z][A-Z]|)

my $path=".";

opendir(DIR, $path)     or die "cannot open directory $path: $!\n";

my @dirs = map  { $_->[1] }        
        grep { -d $_->[1] }
        map  { [ $_, "$path/$_" ] }        
        grep { /^[a-z][a-z](_[A-Z][A-Z]|)$/ }
        readdir(DIR);

closedir(DIR);

# BUT, at the moment only the following translation are ready and will be
# included 
@dirs = ( 'ja', 'cy', 'es', 'fi', 'it', 'nl', 'ro', 'sl_SI', 'zh', 'bg', 'cs',
    'en_GB', 'fr', 'hu', 'no', 'pt', 'ru', 'sv', 'tr', 'zh_CN', 'bs', 'de',
    'en_US', 'gl', 'id', 'ko', 'nb', 'pl', 'pt_BR', 'sk', 'ta', 'tv', 'zh_TW');


$0 =~ m/([^\/]*)$/;
my $progname = $1;

# Usage message
sub usage {
    print <<EOF;
$progname version 0.2
Extracts the Unicode UTF-8 character codes used in "gettext" message files.

$progname [-d <selector>] [-l <lang_dir>]

Options:
    -d <selector>           set debugging selector 
    -l <lang_dir>           only process this language subdirectory 
EOF
}

# parse command line options
if (! getopts('d:l:')) { usage; exit 1; }
if (defined $opt_d) { $debug = $opt_d; }
if (defined $opt_l) { @dirs = ( $opt_l ); }

# These are the language directories we have to parse for a given font file
# name prefix; also, the coderanges that are extracted at the end for this
# font are given here.
# FIXME :
# - what is the correct name for SuSESans?
# - any fonts missing or misclassified?
# - how do I handle directory "zh"; is it obsolete?
# - should we always map Kana (3040-30FF) to a Japanese font?
#   No, because the would not look nice together with a Chinese font.
#   Currently the Kana are at the wrong code positions in the AR PL fonts.
#   But we will fix this if necessary in the fonts.
# - should we always map Bopomofo (3100-312F, 31A0-31BF) to a Chinese font?
#   No, same argument as for Kana.
# - are there other ranges that should be statically assigned to a specific
#   font (e.g. 3200-327F -> Korean, 3280-33FF -> Japanese)?
#

my @fontspecs = (
    'SuSESans'    ,  [ @dirs ]    , [ [ 0x0000, 0x2E7F ] ],
    'FreeSans'    ,  [ @dirs ]    , [ [ 0x0000, 0x2E7F ] ],
    'kochi-'      ,  [ 'ja' ]     , [ [ 0x2E80, 0x312F ], [ 0x3190, 0x9FFF ], [ 0xF900, 0xFAFF ] ],
    'bkai'        ,  [ 'zh_TW' ]  , [ [ 0x2E80, 0x312F ], [ 0x3190, 0x9FFF ], [ 0xF900, 0xFAFF ] ],
    'bsmi'        ,  [ 'zh_TW' ]  , [ [ 0x2E80, 0x312F ], [ 0x3190, 0x9FFF ], [ 0xF900, 0xFAFF ] ],
    'gkai'        ,  [ 'zh_CN' ]  , [ [ 0x2E80, 0x312F ], [ 0x3190, 0x9FFF ], [ 0xF900, 0xFAFF ] ],
    'gbsn'        ,  [ 'zh_CN' ]  , [ [ 0x2E80, 0x312F ], [ 0x3190, 0x9FFF ], [ 0xF900, 0xFAFF ] ],
    'batang'      ,  [ 'ko' ]     , [ [ 0x3130, 0x318F ], ],
    'dotum'       ,  [ 'ko' ]     , [ [ 0x3130, 0x318F ], ],
    'gulim'       ,  [ 'ko' ]     , [ [ 0x3130, 0x318F ], ],
    'hline'       ,  [ 'ko' ]     , [ [ 0x3130, 0x318F ], ]
);

my @SuSESansCPA = ();


sub debugprint {
    my ($string, $prefix, $color, $subsys, $hl) = @_;
    if ($debug & $subsys) {
        chomp $string;
        $string =~ s/($hl)/\e[31;01m$1\e[m$color/gi if defined $hl;
        print($color . $prefix . " <$string>\e[m\n");
    }
}

# For simplicity, every font has its own array of codepoints. We only add used
# codepoints to a table when the directory we are in is in the corresponding
# font's set of source directories.
# E.g., for a Japanese font we only want to collect codepoints that come from
# Japanese po-files, i.e. the ones below "ja".
#
# The algorithm for generating the used codepoint arrays is this:
# 1. while scanning a source file, if we are in a source-dir corresponding to
#    the font, put the codepoint into that font array
# 2. when we finally write an array to the font's file, write only the
#    codepoints that fall in the ranges specified for that font
#


sub savecp {
    my ($string) = @_;
    my $uc = 0;
    debugprint("$string\n", "        savecp:", "\e[01m", 4, undef);

    my $l = length($string);
    print "                " if $debug & 8;
    for ( my $i=0; $i<$l; $i++ ) {
        $uc = ord(substr($string, $i, 1));
        printf("%s: %#x ", substr($string, $i, 1), $uc) if $debug & 8;

        # FIXME : now only handling one codepoint array, implement algorithm
        # described above and below
#        foreach ($low, $high) $fontspec[3] {
#            $SuSESansCPA[$uc] = 1, last if ($low <= $uc && $uc <= $high);
#        }
        $SuSESansCPA[$uc] = 1;

    }
    print "\n" if $debug & 8;
    #   for all characters in the string
    #       for all fonts, if current source-dir is in the font's list of dirs
    #           add codepoint to the font's array
    #       done
    #   done
}

# parse a line belonging to a msgstr-entry and add it to the codepoint array;
# concatenate C-style multiline strings and remove C-style "\[abfnrtv0]", while
# interpreting "\[\?'"]", "\[ox][0-9][0-9]"

sub parse_string {
    ($_) = @_;
    chomp;
    debugprint("$_\n", "    parse_string:", "", 2, undef);
    s/^\s*msgstr(\[[^]]*\]|)\s*//io;

    my $instr=0; # are we between quotes?

    CPLOOP:
    {
        savecp("\""),           redo CPLOOP if $instr && /\G\\"/gco;
        $instr=0,               redo CPLOOP if $instr && /\G"/gco;
        $instr=1,               redo CPLOOP if !$instr && /\G"/gco;
                                redo CPLOOP if !$instr && /\G./gco;

        # the last case above handles all characters outside of quotes,
        # so below we can be sure to be within quotes
                                redo CPLOOP if /\G\\[abfnrtv0]/gco;
        savecp($1),             redo CPLOOP if /\G\\([\\?'])/gco;
        savecp(pack("C",oct($1))), redo CPLOOP if /\G\\o([0-7]{3})/gco;
        savecp(pack("C",hex($1))), redo CPLOOP if /\G\\x([0-9a-fA-F]{2})/gco;
        # FIXME : the following Unicode support is incomplete (long forms) and
        # may be wrong
        savecp(pack("U",hex($1))), redo CPLOOP if /\G\\u([0-9a-fA-F]{4})/gco;

        # everything that does not contain an initial character of any of the
        # "inside of quotes" cases above will be put into a string here and
        # codepoints will be saved for the whole string in one call
        savecp($1),             redo CPLOOP if /\G([^\\"]+)/gco;
    }
}

# parse a *.po file and extract the used UTF-8 codepoints in the gettext
# message strings

sub parse_file {
    # find passes the basename of the current file in $_
    my $file = $_;
    return unless ! -d $file && $file =~ /\.po$/io;
    debugprint("$File::Find::dir/$file\n", "parsing file", "", 1, undef);

    open(FH, "<:utf8", $file)   or die "unable to open file $file: $!";

    my $hl="(msgstr|msgid|^#*)";
    while( <FH> ) {
        debugprint("$_", "parse_file:", "\e[36m", 2, $hl);
        next unless $_ =~ /^\s*msgstr/io;
        parse_string($_);

        while( <FH> ) {
            debugprint("$_", "parse_file:", "\e[36m", 2, $hl);
            last unless $_ =~ /^\s*"/i || $_ =~ /^\s*msgstr/io;
            parse_string($_);
        }
    }
    close(FH);
}

# Main loop over all files
find( \&parse_file, @dirs );

#dump_all_arrays();

my $i = 0; my $count = 0;

for ( $i=0; $i < $#SuSESansCPA; $i++ ) {
    if ($SuSESansCPA[$i]) {
        $count++;
        if ($debug & 16) {
            printf("%#4.4x %s\n", $i, chr($i));
        } else {
            printf("%#4.4x\n", $i);
        }
    }
}

print "total used codepoints: $count\n";
