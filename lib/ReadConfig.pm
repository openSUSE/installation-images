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
  $TmpBase %ConfigData RPMFileName SUSystem Print2File $MToolsCfg $AutoBuild
);

use strict 'vars';
use vars qw (
  $Script $BasePath $LibPath $BinPath $CfgPath $ImagePath $DataPath
  $TmpBase %ConfigData $SUBinary &RPMFileName &SUSystem &Print2File $MToolsCfg $AutoBuild
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
#
#
sub RPMFileName
{
  my ($rpm, $file, @f, $x);
  local $_;

  $rpm = shift;

  $file = $ConfigData{'cache_dir'};

  if($ConfigData{'use_cache'} && $file && -f "$file/$rpm.rpm") {

    # print "*$rpm: $file/$rpm.rpm\n";

    return "$file/$rpm.rpm";
  }

  $file = $ConfigData{'tmp_cache_dir'};

  if($file && -d $file) {
    $file .= "/.rpms";
    mkdir $file, 0755 unless -d $file;
    $file .= "/$rpm.rpm";

    # print "#$rpm: $file\n" if -f $file;

    return $file if -f $file;
  }

  undef $file;

  for (`cat $ConfigData{'suse_base'}/find-name-rpm 2>/dev/null`) {
    chomp;
    s/^\.\///;
    if(m#/(\Q$rpm\E|\Q$rpm\E\-[^\-]+\-[^\-]+\.[^.\-]+)\.rpm$#) {
      $file = "$ConfigData{'suse_base'}/$_";
      last;
    }
  }

  if(!$file) {
    @f = glob "$ConfigData{'suse_base'}/$rpm.rpm";
    if($f[0] && -f $f[0]) {
      $file = $f[0];
    }
  }

  if(!$file) {
    @f = glob "$ConfigData{'suse_base'}/$rpm-*-*.rpm";
    for (@f) {
      next if /\.src\.rpm$/;
      if($_ && -f $_ && m#/\Q$rpm\E\-[^\-]+\-[^\-]+\.[^.\-]+\.rpm$#) {
        $file = $_;
        last;
      }
    }
  }

  $x = $ConfigData{'tmp_cache_dir'};

  if($file && $x && -d($x)) {
    $x .= "/.rpms";
    mkdir $x, 0755 unless -d $x;
    if(-d $x) {
      symlink($file, "$x/$rpm.rpm");
    }
  }

  # print "$rpm: $file\n" if $file;

  return $file;
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

sub KernelImg
{
  local $_;
  my ($ki, @k, @k2);

  ($ki, @k) = @_;

  chomp @k;

  for (@k) {
    s#^/boot/##;
    return $ki if $_ eq $ki;
    push @k2, $_ if /^vmlin/ && !/autoconf|config|version/
  }

  return $k2[0] if @k2 == 1;

  return $ki;
}



#
# initialization part
#

delete $ENV{'LANG'};
delete $ENV{'LANGUAGE'};

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

$| = 1;

$_ = $BinPath;
s:^(.+)/$:$1:;
$ENV{PATH} = "/sbin:/usr/sbin:/bin:/usr/bin:/usr/local/bin:$_";

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
  $SUBinary = "/usr/bin/sw" if -x "/usr/bin/sw";
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

{
  # set suse_release, suse_base, suse_xrelease
  # kernel_ver
  # (used to be in etc/config)

  my ( $r, $r0, $rx, $in_abuild, $base, $a, $v, $kv, $kn, $rf, $work, $ki, @f, $prod );
  my ( $theme, $real_arch, $ul_release, $sles_release, $load_image, $yast_theme, $splash_theme, $product_name, $update_dir );

  $a = $ENV{'suse_arch'};

  $in_abuild = 0;

  if(-f "/.buildenv") {
    open F, "/.buildenv";
    @f = grep !/^\s*(#|$)/, (<F>);
    close F;
    for (@f) {
      if(/^\s*(\S+)\s*=\s*(.*)$/) {
        $ENV{$1} = `echo -n $2`;
      }
    }
    $in_abuild = 1 if $ENV{'BUILD_BASENAME'};
  }

  $prod = "SuSE Linux";

  if($in_abuild) {
    if(-f "/etc/SuSE-release") {
      $r0 = `grep VERSION /etc/SuSE-release`;
    }
    elsif(-f "/etc/UnitedLinux-release") {
      $prod = "UnitedLinux";
      $r0 = `grep VERSION /etc/UnitedLinux-release`;
    }
    $r0 =~ s/^.*=\s*//;
    $r0 =~ s/\s*$//;
    $r0 = "\L$r0";
  }
  else {
    $r0 = $ENV{'suserelease'};
  }

  $r0 = "" unless defined $r0;
  $rf = $r0;

  $rx = "";
  $rx = "$1-" if $r0 =~ s/-(.+)\s*$//;
  $r0 = $1 if $r0 =~ /^(\d+\.\d+)/;
  $r0 = "$r0-" if $r0 ne "";
  $work = defined($ENV{'work'}) && -d($ENV{'work'}) ? $ENV{'work'} : "/work";
  $work .= "/CDs";
  $work .= "/all" if -d "$work/all";
  $base = "$work/full-$rf-$a/suse";
  $base = "$work/full-$a/suse" unless -d $base;
  $ConfigData{'suse_base'} = $ENV{'suse_base'} = "$base/*";

  if(!$in_abuild) {
    # die "Sorry, no packages in \"$work\"!\n" unless -d "$base";
    my $suserelpack = RPMFileName "aaa_version";
    $suserelpack = RPMFileName "unitedlinux-release" unless $suserelpack && -f($suserelpack);
    die "invalid SuSE release" unless -f $suserelpack;
    system "mkdir /tmp/r$$; cd /tmp/r$$; rpm2cpio $suserelpack | cpio -iud --quiet";

    if(-f "/tmp/r$$/etc/SuSE-release") {
      $r0 = `grep VERSION /tmp/r$$/etc/SuSE-release`;
    }
    else {
      $prod = "UnitedLinux";
      $r0 = `grep VERSION /tmp/r$$/etc/UnitedLinux-release`;
    }
    $r0 =~ s/^.*=\s*//;
    $r0 =~ s/\s*$//;
    $r0 = "\L$r0";

    $rf = $r0;

    $rx = "$1-" if $r0 =~ s/-(.+)\s*$//;
    $r0 = $1 if $r0 =~ /^(\d+\.\d+)/;
    $r0 = "$r0-" if $r0 ne "";

    system "rm -rf /tmp/r$$";
  }

  if($prod eq "UnitedLinux") {
    if($rf eq "1.0") {
      $r0 = "8.1";
      $rx = "";
    }
  }

  # print "prod = \"$prod\", base = \"$base\", r0 = \"$r0\", rx = \"$rx\", rf = \"$rf\"\n";

  ($ENV{'suse_release'} = $r0) =~ s/-?$//;
  ($ENV{'suse_xrelease'} = $rx) =~ s/-?$//;

  ($v = "$r0$rx") =~ s/-?$//;

  if(!exists($ENV{'pre_release'})) {
    $ENV{'pre_release'} = $rf =~ /^\d+\.\d+(a\b|\.99)$/ ? 1 : 0;
  }

  if($rf =~ /^(\d+)\.(\d+)\.[5-9]/) {
    $v = "$1." . ($2 + 1);
    $ENV{'suse_release'} = $v;
  }

  # there is no 7.4
  if($ENV{'suse_release'} eq "7.4" && $ENV{'pre_release'}) {
    $ENV{'suse_release'} = $v = "8.0";
  }

  my $cache_dir = `pwd`;
  chomp $cache_dir;
  my $tmp_cache_dir = $cache_dir;
  $cache_dir .= "/${BasePath}cache/$ENV{'suse_release'}-$ENV{'suse_arch'}";
  $ConfigData{'cache_dir'} = $cache_dir;
  $tmp_cache_dir .= "/${BasePath}tmp/cache/$ENV{'suse_release'}-$ENV{'suse_arch'}";
  $ConfigData{'tmp_cache_dir'} = $tmp_cache_dir;
  system "mkdir -p $tmp_cache_dir" unless -d $tmp_cache_dir;
  my $use_cache = 0;

  $ENV{'cache'} = 4 unless exists $ENV{'cache'};
  $use_cache = $ENV{'cache'} if exists $ENV{'cache'};
  $ConfigData{'use_cache'} = $use_cache;

  if($in_abuild) {
    $ENV{kernel_img} = KernelImg $ENV{kernel_img}, (`ls /boot/*`);
    undef $kn;

    $kn = `rpm -qf /boot/$ENV{kernel_img} | head -1 | cut -d- -f1` if -f "/boot/$ENV{kernel_img}";
    chomp $kn if $kn;

    if($ENV{kernel}) {
      $ENV{kernel_rpm} = $ENV{kernel};
    }
    elsif($kn) {
      $ENV{kernel_rpm} = $kn;
    }
    die "oops: unable to determine kernel rpm (looking for /boot/$ENV{kernel_img})" unless $ENV{'kernel_rpm'};

    $kv = `rpm -ql $ENV{'kernel_rpm'} 2>/dev/null | grep modules | head -1 | cut -d / -f 4`;
  }
  else {
    $kv = RPMFileName $ENV{'kernel_rpm'};

    $ENV{'kernel_img'} = KernelImg $ENV{'kernel_img'}, (`rpm -qlp $kv 2>/dev/null | grep /boot`);

    $kv = `rpm -qlp $kv 2>/dev/null | grep modules | head -1 | cut -d / -f 4`;
  }
  chomp $kv;

  $ENV{'kernel_ver'} = $kv;

  if($ENV{'suse_release'} !~ /^(\d+)\.(\d+)$/) {
    die "invalid SuSE release";
  }

  if($in_abuild) {
    $r = $ENV{'BUILD_BASENAME'};
    if(!($r && -d("/.rpm-cache/$r"))) {
      system "ls -la /.rpm-cache";
      die "No usable /.rpm-cache (looking for \"$r\")!\n"
    }
    $ConfigData{'suse_base'} = $ENV{'suse_base'} = $base = $AutoBuild = "/.rpm-cache/$r"
  }

  $ENV{product} = $prod unless $ENV{product};

  $theme = $ENV{theme} ? $ENV{theme} : "SuSE";

  $real_arch = `uname -m`;
  chomp $real_arch;
  $real_arch = "i386" if $real_arch =~ /^i.86$/;

  $ul_release = "ul1";
  $sles_release= "sles8";

  if($theme eq "SuSE") {
    $yast_theme = "SuSELinux";
    $splash_theme = "SuSE";
    $product_name = "SuSE Linux";
    $update_dir = "/linux/suse/$real_arch-$ENV{suse_release}";
    $load_image = "";
  }
  elsif($theme eq "UnitedLinux") {
    $yast_theme = "UnitedLinux";
    $splash_theme = "UnitedLinux";
    $product_name = "UnitedLinux";
    $update_dir = "/linux/UnitedLinux/$real_arch-$ul_release";
    $load_image = 96*1024;
  }
  elsif($theme eq "SuSE-SLES") {
    $yast_theme = "SuSELinux";
    $splash_theme = "SuSE-SLES";
    $product_name = "SuSE Linux";
    $update_dir = "/linux/suse/$real_arch-$sles_release";
    $load_image = 96*1024;
  }
  elsif($theme eq "UL-SLES") {
    $yast_theme = "SuSELinux";
    $splash_theme = "SuSE-SLES";
    $product_name = "SuSE Linux";
    $update_dir = "/linux/UnitedLinux/$real_arch-$ul_release";
    $load_image = 96*1024;
  }
  else {
    die "don't know theme \"$theme\""
  }

  $ENV{theme} = $theme;
  $ENV{yast_theme} = $yast_theme;
  $ENV{splash_theme} = $splash_theme;
  $ENV{product_name} = $product_name;
  $ENV{update_dir} = $update_dir;
  $ENV{load_image} = $load_image;

  for (qw (kernel_img kernel_rpm kernel_ver suse_release suse_xrelease suse_base pre_release theme product product_name yast_theme splash_theme update_dir load_image) ) {
    $ConfigData{$_} = $ENV{$_}
  }

  die "No SuSE release identified.\n" unless $a ne "" && $v ne "";

  $v .= " [$rf]" if $v ne $rf;

  if(!exists $ENV{silent}) {
    my $p = $ENV{'pre_release'} ? "pre-" : "";
    print "Building for $product_name $p$v ($ConfigData{theme},$a,$ENV{'kernel_rpm'}:$ENV{'kernel_img'},$ENV{'kernel_ver'}) [$base].\n";
  }

  # print "<$ENV{'suse_release'}><$ENV{'suse_xrelease'}>\n";
}

1;
