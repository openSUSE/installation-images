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


#
# return list of kernel images
#
sub KernelImg
{
  local $_;
  my ($k_regexp, @k_files, @k_images, @kernels);

  ($k_regexp, @k_files) = @_;

  chomp @k_files;

  for (@k_files) {
    s#^/boot/##;
    next if /autoconf|config|shipped|version/;		# skip obvious garbage
    push @k_images, $_ if m#$k_regexp#;
  }

  return @k_images;
}


sub version_sort
{
  my ($i, $j);

  $i = $ConfigData{ini}{Version}{$a};
  $j = $ConfigData{ini}{Version}{$b};

  $i =~ s/,([^,]+)//;
  $j =~ s/,([^,]+)//;

  return $i <=> $j;
}


# - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - -
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


# - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - -
#
# set arch
#

my ($arch, $realarch, $susearch);

$arch = `uname -m`;
chomp $arch;
$arch = "i386" if $arch =~ /^i.86$/;
$realarch = $arch;
$arch = "sparc" if $arch eq 'sparc64';

$susearch = $arch;
$susearch = 'axp' if $arch eq 'alpha';

$ConfigData{arch} = $arch;


# - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - -
#
# read config file & .buildenv
#

{
  my ($f, @f, $sect, $i, $j);

  $f = $CfgPath . "config";
  die "$Script: no config file \"$f\"\n" unless open(F, "$f.$arch") || open(F, $f);

  while(<F>) {
    chomp;
    s/^\s*([#;].*)?//;
    next if $_ eq "";
    if(/^\[(.+)\]/) {
      $sect = $1;
      next;
    }
    if(/^\s*([^=]*?)\s*=\s*(.*?)\s*$/) {
      $ConfigData{ini}{$sect}{$1} = $2 if defined $sect;
      next;
    }
  }

  close F;

  $ConfigData{buildroot} = $ENV{buildroot} ? $ENV{buildroot} : "";

  if(open F, "$ConfigData{buildroot}/.buildenv") {
    while(<F>) {
      chomp;
      s/^\s*([#;].*)?//;
      next if $_ eq "";
      if(/^\s*([^=]*?)\s*=\s*(.*?)\s*$/) {
        $i = $1;
        $j = $2;
        $j = $1 if $j =~ /^\"(.*)\"$/;
        $ConfigData{buildenv}{$i} = $j;
      }
    }
    close F;
  }
}


# - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - -
# kernel image name
#

$ConfigData{kernel_img} = $ConfigData{ini}{KernelImage}{default}
  if $ConfigData{ini}{KernelImage}{default};

$ConfigData{kernel_img} = $ConfigData{ini}{KernelImage}{$arch}
  if $ConfigData{ini}{KernelImage}{$arch};

$ConfigData{kernel_img} = $ENV{kernel_img} if $ENV{kernel_img};


# - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - -
# kernel rpm name
#

$ConfigData{kernel_rpm} = $ConfigData{ini}{KernelRPM}{default}
  if $ConfigData{ini}{KernelRPM}{default};

$ConfigData{kernel_rpm} = $ConfigData{ini}{KernelRPM}{$arch}
  if $ConfigData{ini}{KernelRPM}{$arch};

$ConfigData{kernel_rpm} = $ENV{kernel} if $ENV{kernel};


# - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - -


# print STDERR "kernel_rpm = $ConfigData{kernel_rpm}, kernel_img = $ConfigData{kernel_img}\n";

# print STDERR "BUILD_DISTRIBUTION_NAME = $ConfigData{buildenv}{BUILD_DISTRIBUTION_NAME}\n";
# print STDERR "BUILD_BASENAME = $ConfigData{buildenv}{BUILD_BASENAME}\n";


{
  # set suse_release, suse_base, suse_xrelease
  # kernel_ver
  # (used to be in etc/config)

  my ( $r, $r0, $rx, $in_abuild, $a, $v, $kv, $rf, $ki, @f );
  my ( $theme, $sles_release, $load_image, $yast_theme, $splash_theme, $product_name, $update_dir );

  my ( $dist, $i, $j, $rel, $xrel );

  $in_abuild = $ConfigData{buildenv}{BUILD_BASENAME} ? 1 : 0;

  # print STDERR "abuild = $in_abuild\n";

  if($in_abuild) {

    $dist = $ConfigData{buildenv}{BUILD_BASENAME};

    if(!-d("$ConfigData{buildroot}/.rpm-cache/$dist")) {
      system "ls -la $ConfigData{buildroot}/.rpm-cache";
      die "No usable /.rpm-cache (looking for \"$dist\")!\n"
    }

    $ConfigData{suse_base} = $AutoBuild = "$ConfigData{buildroot}/.rpm-cache/$dist"
  }
  else {
    my ($work, $base, $xdist);

    $dist = $susearch;

    $work = $ENV{work};
    $work = "/work" if !$work;
    $work = "/mounts/work" if ! -d "$work/CDs";
    $work .= "/CDs";
    $work .= "/all" if -d "$work/all";

    $xdist = $ENV{dist} ? $ENV{dist} : $ENV{suserelease};

    if($xdist) {
      $base = "$work/full-$xdist/suse";
      $dist = $xdist if -d $base;
      if(! -d $base) {
        $base = "$work/full-$xdist-$dist/suse";
        $dist = "$xdist-$dist" if -d $base;
      }
    }
    else {
      $base = "$work/full-$dist/suse";
    }

    die "Sorry, could not locate packages for \"$dist\".\n" unless -d $base;

    $ConfigData{suse_base} = "$base/*";

  }

  $ConfigData{dist} = $dist;

  # print STDERR "base = $ConfigData{suse_base}\n";

  $i = $dist;

  while(!($rel = $ConfigData{ini}{Version}{$i}) && $i =~ s/-[^\-]+$//) {}
  $rel = $ConfigData{ini}{Version}{default} if !$rel && $dist !~ /-/;

  die "Sorry, \"$ConfigData{dist}\" is not supported.\n" unless $rel;

  $xrel = $1 if $rel =~ s/,([^,]+)//;

  # print STDERR "rel = $rel ($xrel)\n";

  $ConfigData{suse_release} = $rel;
  $ConfigData{suse_xrelease} = $xrel;

  my $cache_dir = `pwd`;
  chomp $cache_dir;
  my $tmp_cache_dir = $cache_dir;
  $cache_dir .= "/${BasePath}cache/$ConfigData{dist}";
  $ConfigData{'cache_dir'} = $cache_dir;
  $tmp_cache_dir .= "/${BasePath}tmp/cache/$ConfigData{dist}";
  $ConfigData{'tmp_cache_dir'} = $tmp_cache_dir;
  system "mkdir -p $tmp_cache_dir" unless -d $tmp_cache_dir;
  my $use_cache = 0;

  $ENV{'cache'} = 4 unless exists $ENV{'cache'};
  $use_cache = $ENV{'cache'} if exists $ENV{'cache'};
  $ConfigData{'use_cache'} = $use_cache;

  if($in_abuild) {
    my (@k_images2, %k_rpms);

    my @k_images = KernelImg $ConfigData{kernel_img}, (`find $ConfigData{buildroot}/boot -type f`);

    if(!@k_images) {
      die "Error: No kernel image identified! (Looking for \"$ConfigData{kernel_img}\" in \"$ConfigData{kernel_rpm}\".)\n\n";
    }

    $i = $ConfigData{buildroot} ? "-r $ConfigData{buildroot}" : "";

    for (@k_images) {
      $j = `rpm $i -qf /boot/$_ | head -n 1 | sed 's/-[^-]*-[^-]*\$//'` if -f "$ConfigData{buildroot}/boot/$_";
      chomp $j;
      undef $j if $j =~ /^file /;	# avoid "file ... not owned by any package"
      $k_rpms{$_} = $j if $j;
      if($j && $j eq $ConfigData{kernel_rpm}) {
        push @k_images2, $_;
      }
    }

    if(@k_images == 1) {
      # ok, use just this one
      $ConfigData{kernel_img} = $k_images[0];
    }
    else {
      if(!@k_images2) {
        die "Error: No kernel image identified! (Looking for \"$ConfigData{kernel_img}\" in \"$ConfigData{kernel_rpm}\".)\n\n";
      }
      elsif(@k_images2 > 1) {
        warn
          "Warning: Can't identify the real kernel image, choosing the first:\n",
          join(", ", @k_images2), "\n\n";
      }
      $ConfigData{kernel_img} = $k_images2[0];
    }
    $ConfigData{kernel_rpm} = $k_rpms{$ConfigData{kernel_img}} if $k_rpms{$ConfigData{kernel_img}};

    $kv = `rpm $i -ql $ConfigData{kernel_rpm} 2>/dev/null | grep modules | head -n 1 | cut -d / -f 4`;
  }
  else {
    $i = RPMFileName $ConfigData{kernel_rpm};

    my @k_images = KernelImg $ConfigData{kernel_img}, (`rpm -qlp $i 2>/dev/null | grep ^/boot`);

    if(!@k_images) {
      die "Error: No kernel image identified! (Looking for \"$ConfigData{kernel_img}\".)\n\n";
    }

    if(@k_images != 1) {
      warn "Warning: Can't identify the real kernel image, choosing the first:\n", join(", ", @k_images), "\n\n";
    }

    $ConfigData{kernel_img} = $k_images[0];

    $kv = `rpm -qlp $i 2>/dev/null | grep modules | head -n 1 | cut -d / -f 4`;
  }
  chomp $kv;

  $ConfigData{kernel_ver} = $kv;

  $ConfigData{module_type} = $kv =~ /^2\.[0-4]\./ ? "o" : "ko";

  # print STDERR "kernel_img = $ConfigData{kernel_img}\n";
  # print STDERR "kernel_rpm = $ConfigData{kernel_rpm}\n";
  # print STDERR "kernel_ver = $ConfigData{kernel_ver}\n";

  $theme = $ENV{theme} ? $ENV{theme} : "SuSE";

  for $i (sort version_sort keys %{$ConfigData{ini}{Version}}) {
    $j = $ConfigData{ini}{Version}{$i};
    $j =~ s/,([^,]+)//;
    if($j <= $ConfigData{suse_release}) {
      $sles_release = $i if $i =~ /^sles/;
    }
  }

  die "Oops, no SLES release number found\n" unless $sles_release;

  # print STDERR "sles = $sles_release\n";

  die "Don't know theme \"$theme\"\n" unless exists $ConfigData{ini}{"Theme $theme"};

  if($ENV{themes}) {
    my %t;
    @t{split ' ', $ENV{themes}} = ();
    die "Theme \"$theme\" not supported\n" unless exists $t{$theme};
  }

  $yast_theme = $ConfigData{ini}{"Theme $theme"}{yast};
  $splash_theme = $ConfigData{ini}{"Theme $theme"}{splash};
  $product_name = $ConfigData{ini}{"Theme $theme"}{product};
  my $full_product_name = $product_name;
  $full_product_name .= (" " . $ConfigData{ini}{"Theme $theme"}{version}) if $ConfigData{ini}{"Theme $theme"}{version};
  $update_dir = $ConfigData{ini}{"Theme $theme"}{update};
  $update_dir =~ s/<sles>/$sles_release/g;
  $update_dir =~ s/<rel>/$rel/g;
  $update_dir =~ s/<arch>/$realarch/g;
  $load_image = $ConfigData{ini}{"Theme $theme"}{image};
  $load_image = $load_image * 1024 if $load_image;

  $ConfigData{theme} = $theme;
  $ConfigData{yast_theme} = $yast_theme;
  $ConfigData{splash_theme} = $splash_theme;
  $ConfigData{product_name} = $product_name;
  $ConfigData{full_product_name} = $full_product_name;
  $ConfigData{update_dir} = $update_dir;
  $ConfigData{load_image} = $load_image;

  $ConfigData{min_memory} = $ConfigData{ini}{"Theme $theme"}{memory};

  # print STDERR "yast_theme = $ConfigData{yast_theme}\n";
  # print STDERR "splash_theme = $ConfigData{splash_theme}\n";
  # print STDERR "product_name = $ConfigData{product_name}\n";
  # print STDERR "update_dir = $ConfigData{update_dir}\n";
  # print STDERR "load_image = $ConfigData{load_image}\n";

  $ConfigData{kernel_mods} = $ConfigData{kernel_ver};
  $ConfigData{kernel_mods} =~ s/-(.+?)-/-override-/;

  if(!$ENV{silent}) {
    my $r;

    $r = $ConfigData{suse_release};
    $r .= " $ConfigData{suse_xrelease}" if $ConfigData{suse_xrelease};

    print "--- Building for $product_name $r $ConfigData{arch} ($sles_release), theme $ConfigData{theme}\n";
    print "--- Kernel: $ConfigData{kernel_rpm}, $ConfigData{kernel_img}, $ConfigData{kernel_ver}\n";

    $r = $ConfigData{suse_base};
    $r =~ s/\/\*$//;
    print "--- Source: $r\n";
  }
}

1;
