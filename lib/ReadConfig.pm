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
  $TmpBase %ConfigData ReadFile RealRPM RealRPMs ReadRPM $SUBinary SUSystem Print2File $MToolsCfg $AutoBuild
  ResolveDeps CopyRPM
);

use strict 'vars';
use vars qw (
  $Script $BasePath $LibPath $BinPath $CfgPath $ImagePath $DataPath
  $TmpBase %ConfigData $SUBinary &RPMFileName &SUSystem &Print2File $MToolsCfg $AutoBuild
  $rpmData
);

use Cwd;
use File::Path 'make_path';
use File::Spec 'abs2rel';

eval "use solv";

sub api_get;
sub api_get_file;
sub api_post;
sub get_repo_list;
sub read_meta;
sub read_packages;
sub resolve_deps_obs;
sub resolve_deps_libsolv;
sub show_package_deps;
sub get_version_info;
sub version_cmp;

my ($arch, $realarch, $susearch);

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


sub ResolveDeps
{
  local $_;
  my $packages = shift;
  my $ignore = shift;
  my $old = shift;

  my $p1;

  if($ConfigData{obs}) {
    $p1 = resolve_deps_obs $packages, $ignore;
  }
  else {
    die "oops, no libsolv" unless $ConfigData{libsolv_ok};
    $p1 = resolve_deps_libsolv $packages, $ignore;
  }

  my $p2;

  my $cnt = 0;
  for (keys %$p1) {
    next if $old->{$_};
    $p2->{$_} = show_package_deps($_, $p1);
    $cnt++;
  }

  for (sort keys %$p2) {
    print "  $p2->{$_}\n";
  }
  print "== $cnt packages ==\n";

  return $p2;
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
  my ($f, @f, @ff, $p, $back, $n, %n, $r, $rpm_orig);

  return $rpmData->{$rpm} if exists $rpmData->{$rpm};

  $rpm_orig = $rpm;

  $back = 1 if $rpm =~ s/~$//;

  if($ConfigData{obs}) {
    $p = $rpm;
    $p = "\Q$p";
    $p =~ s/\\\*/([0-9_]+)/g;
    @f = grep { /^$p / } @{$ConfigData{packages}};

    return $rpmData->{$rpm_orig} = undef if @f == 0;

    @f = sort { &version_cmp } @f;
    # for (@f) { print ">$_<\n"; }
    $f = pop @f;
    $f = pop @f if $back;

    if($f =~ m/^(\S+) (.+)$/) {
      return $rpmData->{$1} = $rpmData->{$rpm_orig} = { name => $1, file => "$ConfigData{tmp_cache_dir}/.obs/$2/$1.rpm", rfile => "../.obs/$2/$1.rpm", obs => "$2" };
    }
    else {
      return $rpmData->{$rpm_orig} = undef;
    }
  }
  else {
    my $dir = $ConfigData{suse_base};

    @f = grep { -f } <$ConfigData{cache_dir}/$rpm.rpm $dir/$rpm.rpm>;
    for (@f) {
      $n = $_;
      s#^.*/|\.rpm$##g;
      $n{$_} = $n unless exists $n{$_};
    }

    return $rpmData->{$rpm_orig} = undef if @f == 0;

    $p = $rpm;
    $p = "\Q$p";
    $p =~ s/\\\*/([0-9_]+)/g;
    @f = grep { /^$p$/ } @f;
    @f = sort @f;
    # for (@f) { print ">$_<\n"; }
    $f = pop @f;
    $f = pop @f if $back;

    return $rpmData->{$f} = $rpmData->{$rpm_orig} = { name => $f, file => $n{$f} } ;
  }
}


# Return list of RPMs matching (regexp) pattern. The list is empty if no
# match was found.
#
sub RealRPMs
{
  my $pattern = shift;
  my @packages;

  if($ConfigData{obs}) {
    # running outside obs
    @packages = @{$ConfigData{packages}};
    # entries in ConfigData are "PACKAGE PROJECT", remove the PROJECT part
    map { s/\s.*$// } @packages;
  }
  else {
    # running in an obs build
    @packages = <$ConfigData{suse_base}/*.rpm>;
    # remove superfluous file name parts
    map { s#^.*/|\.rpm$##g } @packages;
  }

  return [ grep { /^$pattern$/ } @packages ];
}


#
# 'rpm' is hash as returned from RealRPM().
#
sub UnpackRPM
{
  my $rpm = shift;
  my $dir = shift;
  my ($log, $i);

  return 1 unless $rpm;

  if($rpm->{obs} && ! -f $rpm->{file}) {
    # retry up to 3 times
    for ($i = 0; $i < 3; $i++) {
      api_get_file "/build/$rpm->{obs}/$ConfigData{obs_arch}/_repository/$rpm->{name}.rpm", $rpm->{file}, \$log;
      last if -f $rpm->{file};
    }
    if(! -f $rpm->{file}) {
      print STDERR "$rpm->{file}: $ConfigData{obs_server}/build/$rpm->{obs}/$ConfigData{obs_arch}/_repository/$rpm->{name}.rpm\n" . $log;
      warn "$Script: failed to download $rpm->{name}";
      return 1
    }
  }

  if(SUSystem "sh -c 'cd $dir ; rpm2cpio $rpm->{file} | cpio --quiet --sparse -dimu --no-absolute-filenames'") {
    print STDERR "$rpm->{file}: $ConfigData{obs_server}/build/$rpm->{obs}/$ConfigData{obs_arch}/_repository/$rpm->{name}.rpm\n" . $log;
    warn "$Script: failed to extract $rpm->{name}";
    return 1;
  }

  symlink($rpm->{rfile} ? $rpm->{rfile} : $rpm->{file}, "$ConfigData{tmp_cache_dir}/.rpms/$rpm->{name}.rpm");

  return 0;
}


#
# Unpack rpm_name to target_dir and return path to cache dir or undef if failed.
#
sub CopyRPM
{
  my $rpm_name = $_[0];
  my $target_dir = $_[1];

  my $cache_dir = ReadRPM($rpm_name);
  if($cache_dir) {
    system "tar -C '$cache_dir/rpm' -cf - . | tar -C '$target_dir' -xf -";
  }

  return $cache_dir;
}


#
# Unpack rpm to cache dir and return path to dir or undef if failed.
#
sub ReadRPM
{
  local $_;
  my ($s, $f, @s);

  my $rpm = RealRPM $_[0];

  if(!$rpm || !$rpm->{name}) {
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

    $_ = `$rpm_cmd -qp --provides $rpm->{file} 2>/dev/null`;
    open $f, ">$dir/provides";
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

    CopyRPM "$rpm->{name}-base", $tdir;
    CopyRPM "$rpm->{name}-extra", $tdir;
    CopyRPM "$rpm->{name}-optional", $tdir;

    my $kmp;
    for (split(',', $ConfigData{kmp_list})) {
      ($kmp = $rpm->{name}) =~ s/^kernel/$_-kmp/;
      print "adding kmp $kmp\n";
      CopyRPM $kmp, $tdir;
    }

    for (split(',', $ConfigData{fw_list})) {
      if($_ eq 'kernel-firmware-all') {
        my $rpm = ReadRPM($_);
        if($rpm) {
          my $deps = ReadFile "$rpm/requires";
          for my $fw (split /\n/, $deps) {
            if($fw =~ /^(kernel-firmware-\S+)/) {
              $fw = $1;
              print "adding firmware $fw\n";
              CopyRPM $fw, $tdir;
            }
          }
        }
      }
      else {
        print "adding firmware $_\n";
        CopyRPM $_, $tdir;
      }
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

    # unpack kernel modules if requested
    # see doc/compression.md
    if($ENV{instsys_no_compression} =~ /modules/) {
      my $dir = "$tdir/usr/lib/modules";
      $dir = "$tdir/lib/modules" if ! -d $dir;

      print "uncompressing kernel modules...\n";

      SUSystem "find $dir -type f -name \*.ko.zst -exec zstd -d --quiet --rm '{}' \\;";
      SUSystem "find $dir -type f -name \*.ko.xz -exec xz -d '{}' \\;";
      SUSystem "find $dir -type f -name \*.ko.gz -exec gzip -d '{}' \\;";
    }

    # unpack kernel firmware if requested
    # see doc/compression.md
    if($ENV{instsys_no_compression} =~ /firmware/) {
      my $dir = "$tdir/usr/lib/firmware";
      $dir = "$tdir/lib/firmware" if ! -d $dir;

      print "uncompressing kernel firmware...\n";

      # rename symlinks
      for my $suffix ("zst", "xz", "gz") {
        SUSystem "find $dir -type l -name \*.$suffix -exec rename -sl .$suffix '' '{}' \\; -exec rename -l .$suffix '' '{}' \\;";
      }

      # unpack files
      SUSystem "find $dir -type f -name \*.zst -exec zstd -d --quiet --rm '{}' \\;";
      SUSystem "find $dir -type f -name \*.xz -exec xz -d '{}' \\;";
      SUSystem "find $dir -type f -name \*.gz -exec gzip -d '{}' \\;";

      my $broken = `find $dir -follow -type l`;
      die "firmware uncompressing left broken symlinks:\n$broken\n" if $broken ne "";
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
    push @k_images, $_ if m#^$ConfigData{kernel_img}#;
  }

  return @k_images;
}


sub api_get_file
{
  my $api_cmd = $_[0];
  my $file = $_[1];
  my $log = $_[2];
  my $err;

  $$log .= `runuser -u $ConfigData{obs_user} -- osc -A $ConfigData{obs_server} api '${api_cmd}' 2>&1 >$file`;

  $err = $?;

  unlink $file if $err;

  return $err;
}


sub api_get
{
  my $api_cmd = $_[0];
  my @res;

  @res = `runuser -u $ConfigData{obs_user} -- osc -A $ConfigData{obs_server} api '${api_cmd}' 2>/dev/null`;

  return @res;
}


sub api_post
{
  my $api_cmd = $_[0];
  my $file = $_[1];
  my @res;

  # --add-header=Content-Type application/octet-stream
  @res = `runuser -u $ConfigData{obs_user} -- osc -A $ConfigData{obs_server} api -T $file -X POST '${api_cmd}'`;

  return @res;
}


sub get_repo_list
{
  local $_;

  my $prj = shift;
  my $repo = shift;
  my $inrepo;
  my $r = [ ];

  # print "($prj, $repo)\n";

  for (api_get "/source/$prj/_meta") {
    if($inrepo) {
      if(/<path/) {
        my $x;
        $x->[0] = $1 if /\sproject="([^"]+)"/;
        $x->[1] = $1 if /\srepository="([^"]+)"/;
        push @$r, $x if @$x == 2;
        next;
      }
      elsif(/<\/repository>/) {
        last;
      }
    }
    elsif(/<repository.*\sname="\Q$repo\E"/) {
      $inrepo = 1;
      next;
    }
  }

  # for (@$r) { print "> $_->[0] - $_->[1]\n"; }

  return $r;
}


sub read_meta
{
  local $_;

  my $prj = shift;
  my $repo = shift;
  my $list = [[ $prj, $repo ]];
  my %seen;
  my $cnt;

  do {
    $cnt = 0;
    for (@{get_repo_list(@{$list->[-1]})}) {
      if(!$seen{"$_->[0]/$_->[1]"}) {
        push @$list, $_;
        $cnt++;
      }
      $seen{"$_->[0]/$_->[1]"} = 1;
    }
  } while($cnt);

  # for (@$list) { print ">> $_->[0] - $_->[1]\n"; }

  return $list;
}


sub read_packages
{
  local $_;

  my $prj = shift;
  my $repo = shift;
  my ($list, %seen, $l, @packages, $f, $p, $r);

  if(-f "$ConfigData{tmp_cache_dir}/.obs/packages") {
    open $f, "$ConfigData{tmp_cache_dir}/.obs/packages";
    while(<$f>) {
      chomp;
      push @packages, $_;
    }
    close $f;
    if(@packages) {
      $ConfigData{packages} = [ @packages ];
    }
    else {
      die "no packages in $ConfigData{suse_base}\n";
    }

    return;
  }

  print STDERR "Reading OBS meta data...";

  $list = read_meta($prj, $repo);

  open $f, ">", "$ConfigData{tmp_cache_dir}/.obs/repositories";

  for $l (@$list) {
    $p = $l->[0];
    $r = $l->[1];

    print $f "$p $r\n";
    my $new_dir = "$ConfigData{tmp_cache_dir}/.obs/$p/$r";
    make_path $new_dir;
    die "$Script: failed to create $new_dir" unless -d $new_dir;

    for (api_get "/build/$p/$r/$ConfigData{obs_arch}/_repository?view=binaryversions&nometa=1") {
      if(/<binary\s+name="([^"]+)\.rpm"/) {
        push @packages, "$1 $p/$r" unless $seen{$1};
        $seen{$1} = 1;
      }
    }
  }

  close $f;

  # for (@packages) { print "$_\n"; }

  if(@packages) {
    open $f, ">", "$ConfigData{tmp_cache_dir}/.obs/packages";
    for (@packages) { print $f "$_\n" }
    close $f;
    $ConfigData{packages} = [ @packages ];
  }
  else {
    die "no packages in $ConfigData{suse_base}\n";
  }

  print STDERR "\n";
}


sub resolve_deps_obs
{
  local $_;
  my $packages = shift;
  my $ignore = shift;

  my $prj = $ConfigData{obs_proj};
  my $repo = $ConfigData{obs_repo};

  my $t = "$ConfigData{tmp_cache_dir}/.tmp_deps";

  open my $f, ">$t";
  print $f "#!BuildIgnore: simple_expansion_hack\nName: foo\n";
  print $f "BuildRequires: $_\n" for (@$packages);
  print $f "#!BuildIgnore: $_\n" for (@$ignore);
  print $f "#!BuildIgnore: $_\n" for (split /,/, $ENV{ignore_packages});
  close $f;

  my %p;
  my @err;
  my %added;
  my @post_result;

  @post_result = api_post "/build/$prj/$repo/$ConfigData{obs_arch}/_repository/_buildinfo?debug=1", $t;

  for (@post_result) {
    print $_ if $ENV{debug} =~ /solv/;
    $added{$1} = $3 if /^added (\S+?)(\@\S+)? because of (\S+?)(:|$)/;
    $p{$1} = "" if /<bdep\s+name=\"([^"]+)\"/;
    push @err, $1 if /<error>([^<]+)</;
  }

  unlink $t;

  delete $p{$_} for (@$packages);

  if(@err) {
    my $err = join(', ', @err);
    @err = split /, /, $err;
    print "$Script: $_\n" for @err;
    warn "$Script: error solving package deps";
  }

  $p{$_} = $added{$_} for (keys %p);

  return \%p;
}


sub resolve_deps_libsolv
{
  local $_;
  my $packages = shift;
  my $ignore = shift;

  my $ignore_file_deps = $ENV{debug} =~ /filedeps/ ? 0 : 1;

  my %p;

  my $pool = solv::Pool->new();
  my $repo = $pool->add_repo("instsys");
  $repo->add_solv("/tmp/instsys.solv") or die "/tmp/instsys.solv: no solv file";
  $pool->addfileprovides();
  $pool->createwhatprovides();
  $pool->set_debuglevel(4) if $ENV{debug} =~ /solv/;

  my $jobs;
  for (@$packages) {
    push @$jobs, $pool->Job($solv::Job::SOLVER_INSTALL | $solv::Job::SOLVER_SOLVABLE_NAME, $pool->str2id($_));
  }

  my $blackpkg = $repo->add_solvable();
  $blackpkg->{evr} = "1-1";
  $blackpkg->{name} = "blacklist_package";
  $blackpkg->{arch} = "noarch";

  my %blacklisted;
  for (@$ignore) {
    my $id = $pool->str2id($_);
    next if $pool->Job($solv::Job::SOLVER_SOLVABLE_NAME, $id)->solvables();
    $blackpkg->add_deparray($solv::SOLVABLE_PROVIDES, $id);
    $blacklisted{$_} = 1;
  }

  $pool->createwhatprovides();

  if(defined &solv::XSolvable::unset) {
    for (@$ignore) {
      my $job = $pool->Job($solv::Job::SOLVER_SOLVABLE_NAME, $pool->str2id($_));
      for my $s ($job->solvables()) {
        $s->unset($solv::SOLVABLE_REQUIRES);
        $s->unset($solv::SOLVABLE_RECOMMENDS);
        $s->unset($solv::SOLVABLE_SUPPLEMENTS);
      }
    }

    if($ignore_file_deps) {
      for ($pool->Selection_all()->solvables()) {
        my @deps = $_->lookup_idarray($solv::SOLVABLE_REQUIRES, 0);
        @deps = grep { $pool->id2str($_) !~ /^\// } @deps;
        $_->unset($solv::SOLVABLE_REQUIRES);
        for my $id (@deps) {
          $_->add_deparray($solv::SOLVABLE_REQUIRES, $id, 0);
        }
      }  
    }

    if (%blacklisted) {
      for ($pool->Selection_all()->solvables()) {
        my @deps = $_->lookup_idarray($solv::SOLVABLE_CONFLICTS, 0);
        my @fdeps = grep { !$blacklisted{$pool->id2str($_)} } @deps;
        next if @fdeps == @deps;
        $_->unset($solv::SOLVABLE_CONFLICTS);
        for my $id (@fdeps) {
          $_->add_deparray($solv::SOLVABLE_CONFLICTS, $id, 0);
        }
      }
    }
  }
  else {
    warn "$Script: outdated perl-solv: solver will not work properly";
  }

  my $solver = $pool->Solver();
  $solver->set_flag($solv::Solver::SOLVER_FLAG_IGNORE_RECOMMENDED, 1);

  my @problems = $solver->solve($jobs);

  if(@problems) {
    my @err;

    for my $problem (@problems) {
      for my $pr ($problem->findallproblemrules()) {
        push @err, "$Script: " . $pr->info()->problemstr() . "\n";
      }
    }

    warn join('', @err);

    return \%p;
  }

  my $trans = $solver->transaction();

  for ($trans->newsolvables()) {
    my $dep;

    if(defined &solv::Solver::describe_decision) {
      my ($reason, $rule) = $solver->describe_decision($_);
      if ($rule && $rule->{type} == $solv::Solver::SOLVER_RULE_RPM) {
        $dep = $rule->info()->{solvable}{name};
      }
      else {
        # print "XXX $_->{name}: type = $rule->{type}\n";
      }
    }  

    $p{$_->{name}} = $dep;
  }

  delete $p{$_} for (@$packages, @$ignore);
  delete $p{$blackpkg->{name}};

  return \%p;
}


sub show_package_deps
{  
  my $p = shift;
  my $packages = shift;

  my $s = $p;

  my %d;
  $d{$p} = 1;   

  while(($p = $packages->{$p}) ne '' && !$d{$p}) {
    $d{$p} = 1;
    $s .= " < $p";
  }  

  return $s;
}


# Read real version/product info from /etc/os-release.
#
# This only works _after_ we have setup the 'base' system in tmp/base.
#
sub get_version_info
{
  my $file = "${BasePath}tmp/base/etc/os-release";
  my $f;
  my %config;;

  $file = "${BasePath}tmp/base/usr/lib/os-release" if -f "${BasePath}tmp/base/usr/lib/os-release";
  if(open $f, $file) {
    while(<$f>) {
      $config{$1} = $2 if /^([^\s=]+)\s*=\s*\"?(.*?)\"?\s*$/;
    }
  }
  else {
    return;
  }

  # build nice product name

  my $product = $config{PRETTY_NAME};
  $product =~ s/\s*\([^)]*\)$//;
  $product =~ s/\s+(Server|Desktop)\s+/ /;

  # print "product=\"$product\"\n";

  $ConfigData{os}{product} = $product;

  # the same without anything in parentheses

  my $product_mini = $product;
  $product_mini =~ s/\s*\(.*//;

  # print "product_mini=\"$product_mini\"\n";

  $ConfigData{os}{product_mini} = $product_mini;

  $ConfigData{os}{product_short} = $config{NAME};
  $ConfigData{os}{product_short} .= "-$config{VERSION}" if $config{VERSION};

  # get dist tag for driver updates

  my $dist = "\L$config{NAME}";
  $dist =~ s/^opensuse[\-\s]*//;
  # special enterprise products may have extra text beside SLES or SLED
  $dist = $1 if $dist =~ /(sles|sled)/;

  # unified installer uses "sle" but we map everything to "sles" as this is
  # what people are used to
  $dist = "sles" if $dist eq "sle";

  # SUSE MicroOS is kept called MicroOS insternally, but the product NAME
  # is now SLE Micro
  $dist = "suse-microos" if $dist eq "sle micro";
  $dist = "suse-microos" if $dist eq "leap micro";

  # don't accept other names than these

  die "*** unsupported product: $dist ***" if $dist !~ /^(casp|caasp|kubic|microos|suse-microos|leap|sles|sled|tumbleweed( kubic)?)$/;

  # Kubic is based on TW
  # MicroOS can be based on TW or Leap

  my $is_tw = $dist =~ /^tumbleweed( kubic)?$/;

  if($dist eq "microos") {
    if($config{ID_LIKE} =~ /tumbleweed/) {
      $is_tw = 1;
    }
    elsif($config{ID_LIKE} =~ /leap/) {
      $dist = "leap";
    }
  }

  $dist = $is_tw ? 'tw' : "$dist$config{VERSION_ID}";

  # there's no separate dist tag for service packs
  $dist =~ s/\..*$// if $dist =~ /^(sles|sled)/;

  # caasp uses the dist it is based on (except for caasp1.0)
  $dist = "sles12" if $dist eq "caasp2.0";
  $dist = "sles15" if $dist eq "caasp3.0";

  # print "dist=\"$dist\"\n";

  $ConfigData{os}{update} = "/linux/suse/$realarch-$dist";
}


# compare version strings
#
# Ensuring that e.g. 'foo11' comes after 'foo4'.
#
sub version_cmp
{
  my $x = $a;
  my $y = $b;

  # assume numbers will have at most 10 digits...
  $x =~ s/(\d+)/sprintf "%010s", $1/eg;
  $y =~ s/(\d+)/sprintf "%010s", $1/eg;

  return $x cmp $y;
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

$arch = `uname -m`;
chomp $arch;
$arch = "i386" if $arch =~ /^i.86$/;

$arch = $ENV{TEST_ARCH} if exists $ENV{TEST_ARCH};

$realarch = $arch;
$arch = "sparc" if $arch eq 'sparc64';

$susearch = $arch;
$susearch = 'axp' if $arch eq 'alpha';

$ConfigData{arch} = $arch;
$ConfigData{obs_arch} = $arch eq 'i386' ? 'i586' : $arch;


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
  # set suse_base
  # kernel_ver
  # (used to be in etc/config)

  my ( $r, $r0, $rx, $in_abuild, $a, $v, $kv, $rf, $ki, @f );
  my ( $theme, $load_image, $product_name, $update_dir);

  my ( $dist, $i, $j );

  $in_abuild = $ConfigData{buildenv}{BUILD_BASENAME} ? 1 : 0;
  $in_abuild = 1 if -d "$ConfigData{buildroot}/.build.binaries";

  # print STDERR "abuild = $in_abuild\n";

  die "\nError: *** you must be root to build images ***\n\n" if $>;

  if($in_abuild) {
    my $rpmdir;

    $dist = $ConfigData{buildenv}{BUILD_BASENAME};

    $rpmdir = "$ConfigData{buildroot}/.build.binaries";
    $rpmdir = "$ConfigData{buildroot}/.rpm-cache/$dist" unless -d $rpmdir;

    die "No rpm files found (looking for \"$dist\")!\n" unless -d $rpmdir;

    $ConfigData{suse_base} = $AutoBuild = $rpmdir;

    # if available, setup zypp repo
    if(-x "/usr/bin/rpms2solv") {
      print STDERR "creating solv file...\n";
      if(!-f "/tmp/instsys.solv") {
        system "find /.build.binaries -name '*.rpm' | /usr/bin/rpms2solv -m - >/tmp/instsys.solv" and die "rpms2solv failed";
      }
      $ConfigData{libsolv_ok} = 1;
    }
  }
  elsif($ENV{work} || $ENV{dist}) {
    my ($work, $base, $xdist);

    $dist = $susearch;

    $work = $ENV{work} ? $ENV{work} : "/mounts/dist/full";
    $xdist = $ENV{dist} ? $ENV{dist} : "head-$dist";

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
  else {
    # OBS

    $ConfigData{obs} = 1;

    my ($obs_proj, $obs_repo);

    $ConfigData{obs_proj} = $ConfigData{ini}{OBS}{project};
    $ConfigData{obs_repo} = $ConfigData{ini}{OBS}{repository};
    $ConfigData{obs_server} = $ConfigData{ini}{OBS}{server};

    if($ENV{obs} =~ m#^([^/]+)/([^/]+)[/\-]([^/-]+)$#) {
      $ConfigData{obs_proj} = $1;
      $ConfigData{obs_repo} = $2;
      $ConfigData{obs_arch} = $3;
    }

    if($ENV{obsurl} ne "") {
      $ConfigData{obs_server} = $ENV{obsurl};
    }

    my ($f, $u, $s);

    chomp($ConfigData{obs_user} = `stat --format %U $ENV{HOME}`);

    if($ConfigData{obs_server} !~ /\@/) {
      if(! -f "$ENV{HOME}/.oscrc") {
        die "\nError: *** osc config file ~/.oscrc missing ***\n\n";
      }

      if($< == 0) {
        # to avoid problems with restrictive .oscrc permissions
        open $f, "su `stat -c %U $ENV{HOME}/.oscrc` -c 'cat $ENV{HOME}/.oscrc' |";
      }
      else {
        open $f, "$ENV{HOME}/.oscrc";
      }
      while(<$f>) {
        undef $s if /^\s*\[/;
        $s = 1 if /^\s*\[\Q$ConfigData{obs_server}\E\/?\]/;
        $u = $1 if $s && /^\s*user\s*=\s*(\S+)/;
      }
      close $f;

      if(!defined($u) && $ConfigData{obs_server} =~ /^https:/) {
        die "\nError: *** no authentication data for $ConfigData{obs_server} ***\n\n";
      }
    }

    $ConfigData{suse_base} = "$ConfigData{obs_proj}/$ConfigData{obs_repo}/$ConfigData{obs_arch}";

    ($dist = $ConfigData{suse_base}) =~ tr#/#-#;

    # print "$ConfigData{suse_base}\n";
  }

  $ConfigData{dist} = $dist;

  # print STDERR "base = $ConfigData{suse_base}\n";

  $i = $dist;

  $ConfigData{tmp_path} = "${BasePath}tmp";
  $ConfigData{image_path} = $ImagePath;

  $ConfigData{cache_dir} = getcwd() . "/${BasePath}cache/$ConfigData{dist}";
  $ConfigData{tmp_cache_dir} = getcwd() . "/${BasePath}tmp/cache/$ConfigData{dist}";
  system "mkdir -p $ConfigData{tmp_cache_dir}/.rpms" unless -d "$ConfigData{tmp_cache_dir}/.rpms";

  if($ConfigData{obs}) {
    my ($f, @rpms);
    system "mkdir -p $ConfigData{tmp_cache_dir}/.obs" unless -d "$ConfigData{tmp_cache_dir}/.obs";

    read_packages($ConfigData{obs_proj}, $ConfigData{obs_repo});
  }

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

    my $mod_type = `find $k_dir/rpm/lib/modules/*/kernel/ -type f -name '*.ko*' -print -quit`;
    if (!$mod_type) {
      die "Error: No kernel module found! (Looking for '*.ko*' in '$k_dir/rpm/lib/modules/*/kernel/')\n\n";
    }
    chomp $mod_type;
    $mod_type =~ /\.(ko(?:\.xz|\.zst)?)$/;
    $ConfigData{module_type} = $1;
  }

  # print STDERR "kernel_img = $ConfigData{kernel_img}\n";
  # print STDERR "kernel_rpm = $ConfigData{kernel_rpm}\n";
  # print STDERR "kernel_ver = $ConfigData{kernel_ver}\n";

  $theme = $ENV{theme} ? $ENV{theme} : "openSUSE";

  die "Don't know theme \"$theme\"\n" unless exists $ConfigData{ini}{"Theme $theme"};

  if($ENV{themes}) {
    my %t;
    @t{split ' ', $ENV{themes}} = ();
    die "Theme \"$theme\" not supported\n" unless exists $t{$theme};
  }

  get_version_info();

  $load_image = $ConfigData{ini}{"Theme $theme"}{image};
  $load_image = $load_image * 1024 if $load_image;

  $ConfigData{theme} = $theme;
  for (sort keys %{$ConfigData{ini}{"Theme $theme"}}) {
    next if $_ eq 'image';
    $ConfigData{$_ . '_theme'} = $ConfigData{ini}{"Theme $theme"}{$_};
  }

  $ConfigData{product_name} = $ConfigData{os}{product_mini} || "openSUSE";
  ($ConfigData{product_name_nospaces} = $ConfigData{product_name}) =~ s/\s+/-/g;
  ($ConfigData{product_short} = $ConfigData{product_name_theme} || $ConfigData{os}{product_short} || "SUSE") =~ s/\s+/-/g;
  $ConfigData{update_dir} = $ConfigData{os}{update};
  $ConfigData{load_image} = $load_image;

  $ConfigData{min_memory} = $ConfigData{ini}{"Theme $theme"}{memory};

  $ConfigData{kernel_mods} = $ConfigData{kernel_ver};
  $ConfigData{kernel_mods} =~ s/-(.+?)-/-override-/;

  $ConfigData{instsys_complain} = $ENV{instsys_complain};
  $ConfigData{instsys_complain_root} = $ENV{instsys_complain_root};
  $ConfigData{instsys_build_id} = $ENV{BUILD_ID};

  if(!$ENV{silent}) {
    my ($r, $kmp);

    if($ConfigData{kmp_list}) {
      $kmp = ' (' . join(', ', map { $_ .= "-kmp" } (split(',', $ConfigData{kmp_list}))) . ')';
    }
    else {
      $kmp = "";
    }

    print "--- Building for $ConfigData{product_name} ($ConfigData{product_short}) $ConfigData{arch} [$ConfigData{lib}], theme $ConfigData{theme}\n";
    print "--- Kernel: $ConfigData{kernel_rpm}$kmp, $ConfigData{kernel_img}, $ConfigData{kernel_ver}\n";

    $r = $ConfigData{suse_base};
    $r =~ s/\/\*$//;
    print "--- Source: $r\n";
    print "--- Driver Updates: $ConfigData{update_dir}\n";
  }
}

1;
