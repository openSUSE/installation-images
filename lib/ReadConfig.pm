#! /usr/bin/perl -w

# Read the config file ('etc/config') and set up some useful variables.
# Exports some useful functions, too.
#
# Usage:
#
#   use ReadConfig;
#
#   exported functions:
#     Print2File(file_name, print_args);
#     SUSystem(command);
#
#   exported arrays:
#     %ConfigData
#
#   exported variables:
#     $Script, $BasePath, $LibPath, $BinPath, $CfgPath, $ImagePath,
#     $DataPath, $TmpBase, $MToolsCfg, $AutoBuild
#
#   symbols *not* exported by default:
#     $SUBinary, DebugInfo

=head1 ReadConfig

C<ReadConfig> is a perl module that reads config data from C<etc/config>
initializes a few global variables and exports some useful functions. It
should always be included in scripts operating within the C<bootdisk>
directory hierarchy.

It assumes that the script that included this library was either called from
the base directory or from the C<bin> subdirectory of the base directory.
The base directory itself may be located anywhere.

This is mainly to avoid an environment variable to hold the base directory
(like C<BOOTDISK_ROOT> or something similar).

For the curious: the regular expression used to find the base directory name
from the full script name is:

C<( $0 =~ /(.*?)((?<![^\/])bin\/)?([^\/]+)$/ )[0]>

=head2 Usage

C<BEGIN { unshift @INC, ( $0 =~ /(.*?)((?<![^\/])bin\/)?[^\/]+$/ )[0] . "lib" }>

C<use ReadConfig;>

=head2 Description

=over

=item *

C<Print2File(file_name, print_args)>

C<Print2File(file_name, print_args)> opens the file C<file_name> and prints
to it. C<print_args> are the arguments that would be given to a normal
C<print> command. It's mainly for convenience.

=for html <p>

=item *

C<SUSystem(command)>

C<SUSystem(command)> executes C<command> with root permissions. This
requires a special 'C<sudo>' command to be installed that can give you root
privileges without asking for a password. The name of this command is
C</usr/local/sw> and can only be changed by editing the C<ReadConfig.pm>
file.

This allows you to run the bootdisk scripts as a normal user.

If you don't have such a program or are running the scripts as root, C<SUSystem> is
I<identical> to the usual C<system> command.

You can check if this feature is actually available by looking at the
C<$ReadConfig::SUBinary> variable that holds the name of the 'C<sudo>'
command (or C<undef>).

=for html <p>

=item *

C<%ConfigData>

C<%ConfigData> is an hash table that holds the config info read from C<etc/config>.
C<etc/config> is a shell script that may contain I<only> variable assignments.

=for html <p>

=item *

exported variables

=over

=item *

C<$Script> is the name of the script that included this library (without the path).

=item *

C<$BasePath> holds the name of the base directory.

=item *

C<$LibPath = "$BasePath/lib">.

=item *

C<$BinPath = "$BasePath/bin">. The C<PATH> environment variable is
appropriately extended.

=item *

C<$CfgPath = "$BasePath/etc">.

=item *

C<$ImagePath = "$BasePath/images">.

=item *

C<$DataPath = "$BasePath/data">.

=item *

C<$TmpBase> is the name used for temporary file/directory names.

=item *

C<$MToolsCfg> is the name of a temporary C<mtools> config file. The
C<MTOOLSRC> environment variable is set to point to it.

=back

=for html <p>

=item *

symbols that are not exported

=over

=item *

C<DebugInfo()> prints the current values of some variables.

=item *

C<$SUBinary> (see C<SUSystem> above).

=back

=back

=cut


package ReadConfig;

require Exporter;
@ISA = qw ( Exporter );
@EXPORT = qw (
  $Script $BasePath $LibPath $BinPath $CfgPath $ImagePath $DataPath
  $TmpBase %ConfigData SUSystem Print2File $MToolsCfg $AutoBuild
);

use strict 'vars';
use vars qw (
  $Script $BasePath $LibPath $BinPath $CfgPath $ImagePath $DataPath
  $TmpBase %ConfigData $SUBinary &SUSystem &Print2File $MToolsCfg $AutoBuild
);

sub DebugInfo
{
  local $_;

  print "Script = \"$Script\"\n";
  print "BasePath = \"$BasePath\"\n";
  print "LibPath = \"$LibPath\"\n";
  print "BinPath = \"$BinPath\"\n";
  print "CfgPath = \"$CfgPath\"\n";
  print "ImagePath = \"$ImagePath\"\n";
  print "DataPath = \"$DataPath\"\n";
  print "TmpBase = \"$TmpBase\"\n";
  print "MToolsCfg = \"$MToolsCfg\"\n";

  print "ConfigData:\n";
  for (sort keys %ConfigData) {
    print "  $_ = \"$ConfigData{$_}\"\n"
  }
}

#
# execute string as root
#
sub SUSystem
{
  if($SUBinary) {
    return system "$SUBinary -q 0 $_[0]";
  }
  else {
    return system @_;
  }
}

#
# print to a file
#
sub Print2File
{
  local $_ = shift;

  open Print2File_F, ">$_" or return undef;
  print Print2File_F @_;
  close Print2File_F;

  return 1;
}

#
# initialization part
#

if($0 =~ /(.*?)((?<![^\/])bin\/)?([^\/]+)$/) {
  $Script = $3;
  $BasePath = $1;
  $LibPath = $1 . "lib/";
  $BinPath = $1 . "bin/";
  $CfgPath = $1 . "etc/";
  $ImagePath = $1 . "images/";
  $DataPath = $1 . "data/";
}
else {
  die "OOPS: don't invoke the script that way!\n"
}

if(!(
  ($BasePath eq "" || -d $BasePath) &&
  -d $LibPath &&
  -d $BinPath &&
  -d $CfgPath &&
  -d $ImagePath &&
  -d $DataPath
)) {
  die "$Script: you got it all wrong!\n";
}

$_ = $BinPath;
s:^(.+)/$:$1:;
$ENV{PATH} = "$_:/sbin:/usr/sbin:$ENV{PATH}";

$TmpBase = "/tmp/${Script}_${$}";
$MToolsCfg = "$TmpBase.mtoolsrc";

$ENV{MTOOLSRC} = $MToolsCfg;

# The purpose of this is to allow to run the scripts without having root
# permissions.
#
# The $SUBinary must be a program that gives you superuser rights *without*
# a password.
#
# If you don't have such a program or *are* already root this feature is
# turned off.

if($<) {	# only if we are *not* already root
  $SUBinary = "/usr/local/bin/sw";
  $SUBinary = undef unless -x $SUBinary && -u $SUBinary;
}


#
# now, read the config file
#

my ($f, @f);

$f = $CfgPath . "config";
die "$Script: no config file \"$f\"\n" unless open F, $f;
@f = grep !/^\s*(#|$)/, (<F>);
close F;

#
# only shell variable assignments are allowed
#
for (@f) {
  if(/^\s*(\S+)\s*=\s*(.*)$/) {
    $ENV{$1} = $ConfigData{$1} = `echo -n $2`;
#    print STDERR "<$1> <$ConfigData{$1}>\n";
  }
  else {
    chomp;
    die "$Script: syntax error in config file \"$f\": \"$_\"\n";
  }
}


$AutoBuild = 1 if -f("/bin/rpm.bin") && -f("/bin/uname.bin");

1;
