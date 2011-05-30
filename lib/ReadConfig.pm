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
  $TmpBase %ConfigData ReadFile RealRPM ReadRPM $SUBinary SUSystem Print2File $MToolsCfg $AutoBuild
);

use strict 'vars';
use vars qw (
  $Script $BasePath $LibPath $BinPath $CfgPath $ImagePath $DataPath
  $TmpBase %ConfigData $SUBinary &RPMFileName &SUSystem &Print2File $MToolsCfg $AutoBuild
  $rpmData
);

use Cwd;


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


sub ReadFile
{
  my ($f, $buf);

  open $f, $_[0];
  sysread($f, $buf, -s $_[0]);
  close $f;

  return $buf;
}


#
# Returns hash with 'name' and 'file' keys or undef if package does not
# exist.
#
sub RealRPM
{ 
  local $_;
  my $rpm = shift;
  my ($f, @f, @ff, $p, $back, $n, %n);

  return $rpmData->{$rpm} if exists $rpmData->{$rpm};

  my $dir = $ConfigData{'suse_base'};

  $back = 1 if $rpm =~ s/~$//;

  @f = grep { -f } <$ConfigData{cache_dir}/$rpm.rpm $dir/$rpm.rpm>;
  for (@f) {
    $n = $_;
    s#^.*/|\.rpm$##g;
    $n{$_} = $n unless exists $n{$_};
  }

  return $rpmData->{$rpm} = undef if @f == 0;

  $p = $rpm;
  $p = "\Q$p";
  $p =~ s/\\\*/([0-9_]+)/g;
  @f = grep { /^$p$/ } @f;
  @f = sort @f;
  # for (@f) { print ">$_<\n"; }
  $f = pop @f;
  $f = pop @f if $back;

  return $rpmData->{$f} = $rpmData->{$rpm} = { name => $f, file => $n{$f} } ;
}


#
# 'rpm' is hash as returned from RealRPM().
#
sub UnpackRPM
{
  my $rpm = shift;
  my $dir = shift;

  return 1 unless $rpm;

  if(SUSystem "sh -c 'cd $dir ; rpm2cpio $rpm->{file} | cpio --quiet --sparse -dimu --no-absolute-filenames'") {
    warn "$Script: failed to extract $rpm->{name}";
    return 1;
  }

  symlink($rpm->{file}, "$ConfigData{tmp_cache_dir}/.rpms/$rpm->{name}");

  return 0;
}


#
# Unpack rpm to cache dir and return path to dir or undef if failed.
#
sub ReadRPM
{
  local $_;
  my ($s, $f, @s);

  my $rpm = RealRPM $_[0];

  if(!$rpm) {
    warn "$Script: no such package: $_[0]";
    return undef;
  }

  my $rpm_cmd = "rpm --nosignature";
  my $dir = "$ConfigData{tmp_cache_dir}/$rpm->{name}";
  my $tdir = "$dir/rpm";

  return $dir if -d $dir;

  die "$Script: failed to create $dir ($!)" unless mkdir $dir, 0777;
  die "$Script: failed to create $tdir ($!)" unless mkdir $tdir, 0777;

  my $err = UnpackRPM $rpm, $tdir;

  if(!$err) {
    $_ = `$rpm_cmd -qp --qf '%{VERSION}-%{RELEASE}.%{ARCH}' $rpm->{file} 2>/dev/null`;
    open $f, ">$dir/version";
    print $f $_;
    close $f;

    $_ = `$rpm_cmd -qp --requires $rpm->{file} 2>/dev/null`;
    open $f, ">$dir/requires";
    print $f $_;
    close $f;

    @s = `$rpm_cmd -qp --qf '%|PREIN?{PREIN\n}:{}|%|POSTIN?{POSTIN\n}:{}|%|PREUN?{PREUN\n}:{}|%|POSTUN?{POSTUN\n}:{}|' $rpm->{file} 2>/dev/null`;
    for (@s) {
      chomp;
      $_ = "\L$_";
      $s = `$rpm_cmd -qp --qf '%{\U$_\E}' $rpm->{file} 2>/dev/null`;
      open $f, ">$dir/$_";
      print $f $s;
      close $f;
    }
    if(@s) {
      $s = join ",", @s;
      open $f, ">$dir/scripts";
      print $f "\L$s";
      close $f;
    }
  }

  if(!$err && $rpm->{name} eq $ConfigData{kernel_rpm}) {
    SUSystem "find $tdir -type d -exec chmod a+rx '{}' \\;";

    my $kv;

    $kv = <$tdir/lib/modules/*>;

    if(-d $kv) {
      $kv =~ s#.*/##;
      open $f, ">$dir/kernel";
      print $f $kv;
      close $f;
    }
    else {
      $err = 1;
      undef $kv;
    }

    UnpackRPM RealRPM("$rpm->{name}-base"), $tdir;
    UnpackRPM RealRPM("$rpm->{name}-extra"), $tdir;

    my $kmp;
    for (split(',', $ConfigData{kmp_list})) {
      ($kmp = $rpm->{name}) =~ s/^kernel/$_-kmp/;
      print "adding kmp $kmp\n";
      UnpackRPM RealRPM($kmp), $tdir;
    }

    for (split(',', $ConfigData{fw_list})) {
      print "adding firmware $_\n";
      UnpackRPM RealRPM($_), $tdir;
    }

    # keep it readable
    SUSystem "find $tdir -type d -exec chmod a+rx '{}' \\;";

    # if kmp version differs, copy files to real kernel tree
    for (<$tdir/lib/modules/*>) {
      s#.*/##;
      next if $_ eq $kv;
      print "warning: kmp/firmware version mismatch: $_\n";
      SUSystem "sh -c 'tar -C $tdir/lib/modules/$_ -cf - . | tar -C $tdir/lib/modules/$kv -xf -'";
    }

  }

  return $err ? undef : $dir;
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
  my ($k_files, @k_images);

  $k_files = shift;

  chomp @$k_files;

  for (@$k_files) {
    s#.*/boot/##;
    next if /autoconf|config|shipped|version/;		# skip obvious garbage
    push @k_images, $_ if m#$ConfigData{kernel_img}#;
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

$arch = $ENV{TEST_ARCH} if exists $ENV{TEST_ARCH};

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
# lib directory
#

$ConfigData{lib} = "lib";
$ConfigData{lib} = $ConfigData{ini}{lib}{default} if $ConfigData{ini}{lib}{default};
$ConfigData{lib} = $ConfigData{ini}{lib}{$arch} if $ConfigData{ini}{lib}{$arch};


# - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - -
# kernel rpm name
#

$ConfigData{kernel_rpm} = $ConfigData{ini}{KernelRPM}{default}
  if $ConfigData{ini}{KernelRPM}{default};

$ConfigData{kernel_rpm} = $ConfigData{ini}{KernelRPM}{$arch}
  if $ConfigData{ini}{KernelRPM}{$arch};

$ConfigData{kernel_rpm} = $ENV{kernel} if $ENV{kernel};


# - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - -
# kmp list
#

$ConfigData{kmp_list} = "";

$ConfigData{kmp_list} = $ConfigData{ini}{KMP}{default}
  if $ConfigData{ini}{KMP}{default};

$ConfigData{kmp_list} = $ConfigData{ini}{KMP}{$arch}
  if $ConfigData{ini}{KMP}{$arch};


# - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - -
# firmware list
#

$ConfigData{fw_list} = "";
$ConfigData{fw_list} = $ConfigData{ini}{Firmware}{default} if $ConfigData{ini}{Firmware}{default};
$ConfigData{fw_list} = $ConfigData{ini}{Firmware}{$arch} if $ConfigData{ini}{Firmware}{$arch};


# - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - -


# print STDERR "kernel_rpm = $ConfigData{kernel_rpm}, kernel_img = $ConfigData{kernel_img}\n";

# print STDERR "BUILD_DISTRIBUTION_NAME = $ConfigData{buildenv}{BUILD_DISTRIBUTION_NAME}\n";
# print STDERR "BUILD_BASENAME = $ConfigData{buildenv}{BUILD_BASENAME}\n";


{
  # set suse_release, suse_base, suse_xrelease
  # kernel_ver
  # (used to be in etc/config)

  my ( $r, $r0, $rx, $in_abuild, $a, $v, $kv, $rf, $ki, @f );
  my ( $theme, $sles_release, $load_image, $yast_theme, $splash_theme, $product_name, $update_dir, $sled_release );

  my ( $dist, $i, $j, $rel, $xrel );

  $in_abuild = $ConfigData{buildenv}{BUILD_BASENAME} ? 1 : 0;
  $in_abuild = 1 if -d "$ConfigData{buildroot}/.build.binaries";

  # print STDERR "abuild = $in_abuild\n";

  if($in_abuild) {
    my $rpmdir;

    $dist = $ConfigData{buildenv}{BUILD_BASENAME};

    $rpmdir = "$ConfigData{buildroot}/.build.binaries";
    $rpmdir = "$ConfigData{buildroot}/.rpm-cache/$dist" unless -d $rpmdir;

    die "No rpm files found (looking for \"$dist\")!\n" unless -d $rpmdir;

    $ConfigData{suse_base} = $AutoBuild = $rpmdir;
  }
  else {
    my ($work, $base, $xdist);

    $dist = $susearch;

    $work = $ENV{work};
    if(!$work) {
      $work = "/work";
      $work = "/mounts/work" if ! -d "$work/CDs";
      $work .= "/CDs";
      $work .= "/all" if -d "$work/all";
    }

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

    die "Sorry, could not locate packages for \"$dist\" ($base).\n" unless -d $base;

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

  $ConfigData{cache_dir} = getcwd() . "/${BasePath}cache/$ConfigData{dist}";
  $ConfigData{tmp_cache_dir} = getcwd() . "/${BasePath}tmp/cache/$ConfigData{dist}";
  system "mkdir -p $ConfigData{tmp_cache_dir}/.rpms" unless -d "$ConfigData{tmp_cache_dir}/.rpms";

  my $k_dir = ReadRPM $ConfigData{kernel_rpm};
  if($k_dir) {
    my @k_images = KernelImg [ `find $k_dir/rpm/boot -type f` ];

    if(!@k_images) {
      die "Error: No kernel image identified! (Looking for \"$ConfigData{kernel_img}\".)\n\n";
    }

    if(@k_images != 1) {
      warn "Warning: Can't identify the real kernel image, choosing the first:\n", join(", ", @k_images), "\n\n";
    }

    $ConfigData{kernel_img} = $k_images[0];
    $ConfigData{kernel_ver} = ReadFile "$k_dir/kernel";
    $ConfigData{module_type} = 'ko';
  }

  # print STDERR "kernel_img = $ConfigData{kernel_img}\n";
  # print STDERR "kernel_rpm = $ConfigData{kernel_rpm}\n";
  # print STDERR "kernel_ver = $ConfigData{kernel_ver}\n";

  $theme = $ENV{theme} ? $ENV{theme} : "SuSE";

  for $i (sort version_sort keys %{$ConfigData{ini}{Version}}) {
    $j = $ConfigData{ini}{Version}{$i};
    $j =~ s/,([^,]+)//;
    if($j <= $ConfigData{suse_release}) {
      $sles_release = $i if $i =~ /^sles/;
      $sled_release = $i if $i =~ /^sled/;
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
  $splash_theme = $ConfigData{ini}{"Theme $theme"}{ksplash};
  $product_name = $ConfigData{ini}{"Theme $theme"}{product};
  my $full_product_name = $product_name;
  $full_product_name .= (" " . $ConfigData{ini}{"Theme $theme"}{version}) if $ConfigData{ini}{"Theme $theme"}{version};
  $update_dir = $ConfigData{ini}{"Theme $theme"}{update};
  $update_dir =~ s/<sles>/$sles_release/g;
  $update_dir =~ s/<sled>/$sled_release/g;
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

  $ConfigData{instsys_complain} = $ENV{instsys_complain};
  $ConfigData{instsys_complain_root} = $ENV{instsys_complain_root};
  $ConfigData{instsys_build_id} = $ENV{instsys_build_id};

  if(!$ENV{silent}) {
    my ($r, $kmp);

    $r = $ConfigData{suse_release};
    $r .= " $ConfigData{suse_xrelease}" if $ConfigData{suse_xrelease};

    if($ConfigData{kmp_list}) {
      $kmp = ' (' . join(', ', map { $_ .= "-kmp" } (split(',', $ConfigData{kmp_list}))) . ')';
    }
    else {
      $kmp = "";
    }

    print "--- Building for $product_name $r $ConfigData{arch} [$ConfigData{lib}] ($sles_release,$sled_release), theme $ConfigData{theme}\n";
    print "--- Kernel: $ConfigData{kernel_rpm}$kmp, $ConfigData{kernel_img}, $ConfigData{kernel_ver}\n";

    $r = $ConfigData{suse_base};
    $r =~ s/\/\*$//;
    print "--- Source: $r\n";
  }
}

1;
