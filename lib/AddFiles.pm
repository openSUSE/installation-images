#! /usr/bin/perl -w

# Usage:
#
#   use AddFiles;
#
#   exported functions:
#     AddFiles(dir, file_list, ext_dir);

=head1 AddFiles

C<AddFiles.pm> is a perl module that can be used to extract files from
rpms. It exports the following symbols:

=over

=item *

C<AddFiles(dir, file_list, ext_dir)>

=back

=head2 Usage

use AddFiles;

=head2 Description

=over

=item *

C<AddFiles(dir, file_list, ext_dir)>

C<AddFiles> extracts the files in C<file_list> and puts them into C<dir>.
Files that are not to be taken from rpms are copied from C<ext_dir>.

The syntax of the file list is rather simple; please have a look at those
provided with this package to see how it works. A syntax description follows
later...

On any failure, C<exit( )> is called.


=back

=cut


# - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - -
require Exporter;
@ISA = qw ( Exporter );
@EXPORT = qw ( AddFiles );

use strict 'vars';
use integer;

use Data::Dumper;
$Data::Dumper::Sortkeys = 1;
$Data::Dumper::Terse = 1;
$Data::Dumper::Indent = 1;

use ReadConfig;
use File::Spec;

sub add_pack;
sub _add_pack;
sub find_missing_packs;
sub rpm_has_file;
sub fixup_re;
sub replace_config_var;
sub mount_proc_and_stuff;
sub umount_proc_and_stuff;
sub parse_alternatives;

my $ignore;
my $src_line;
my $templates;
my $used_packs;
my $dangling_links;
my $dir;
my $mount_proc_state;		# cf. (u)mount_proc_and_stuff functions


# - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - -
sub AddFiles
{
  local $_;

  my ($file_list, $ext_dir, $arch, $if_val, $if_taken);
  my ($inc_file, $inc_it, $debug, $ifmsg, $old_warn);
  my ($rpm_dir, $rpm_file, $current_pack);

  my $su = "$SUBinary -q 0 " if $SUBinary;

  ($dir, $file_list, $ext_dir, $dangling_links) = @_;

  $debug = "pkg";
  $debug = $ENV{'debug'} if exists $ENV{'debug'};

  $ignore = $debug =~ /\bignore\b/ ? 1 : 0;

  $old_warn =  $SIG{'__WARN__'};

  $SIG{'__WARN__'} = sub {
    my $x = shift;

    return if $ignore >= 10;

    if($src_line ne '') {
      $x =~ s/\.\n$//;
      $x .= " in $src_line.\n";
    }

    if($ignore) { warn $x } else { die $x }
  };

  $debug .= ',pkg';

  if(! -d $dir) {
    die "$Script: failed to create $dir ($!)" unless mkdir $dir, 0755;
  }

  # - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - -
  # now we really start...

  die "$Script: no such file list: $file_list" unless open F, $file_list;

  $arch = $ConfigData{arch};
  $ENV{'___arch'} = $arch;

  $if_val = $if_taken = 0;

  $current_pack = '';

  my $packs;

  # always has at least one element
  push @$packs, { name => "" };

  my $template_cnt = 0;

  while(1) {
    $_ = $inc_it ? <I> : <F>;

    $src_line = $inc_it ? "$inc_file" : "$file_list";
    $src_line .= " line $.";

    if(!defined($_)) {
      if($inc_it) {
        undef $inc_it;
        close I;
        next;
      } else {
	last;
      }
    }

    chomp;
    next if /^(\s*|\s*#.*)$/;

    s/^\s*//;

    # print STDERR "$_"; <>;

    $ifmsg = sprintf " [%x|%x] %s\n", $if_val, $if_taken, $_;

    s/<rpm_file>/$rpm_file/g;
    s/<(\w+)>/replace_config_var($1)/eg;

    if(/^endif/) {
      $if_val >>= 1;
      $if_taken >>= 1;
      print "*$ifmsg" if $debug =~ /\bif\b/;
      next
    }

    if(/^else/) {
      $if_val &= ~1;
      $if_val |= $if_taken & 1;
      print "*$ifmsg" if $debug =~ /\bif\b/;
      next
    }

    if(/^(els)?if\s+(.+)/) {
      no integer;

      my ( $re, $i, $eif );

      $eif = $1 ? 1 : 0;
      $re = fixup_re $2;
      if($debug =~ /\bif\b/) {
        print "*$ifmsg";
        printf "    # eval \"%s\"\n", $re;
      }
      $ignore += 10;
      $i = eval "if($re) { 0 } else { 1 }";
      $ignore -= 10;
      die "$Script: syntax error in 'if' statement" unless defined $i;
      if($eif) {
        $if_val &= ~1;
        $i = 1 if $i == 0 && ($if_taken & 1) == 1;
      }
      else {
        $if_val <<= 1;
        $if_taken <<= 1;
      }
      $if_val |= $i;
      $if_taken |= 1 - $i;
      next
    }

    if($if_val) {
      print " $ifmsg" if $debug =~ /\bif\b/;
      next
    }

    print "*$ifmsg" if $debug =~ /\bif\b/;

    # set environment var
    if(/^(\w+)\s*=\s*(.*+)\s*$/) {
      my $key = $1;
      my $val = $2;
      $val =~ s/^(['"])(.*)\1$/$2/;
      print "$key = \"$val\"\n" if $debug =~ /\bif\b/;
      $ENV{$key} = $val;
      next;
    }

    if(/^include\s+(\S+)$/) {
      die "$Script: recursive include not supported" if $inc_it;
      $inc_file = $1;
      die "$Script: no such file list: $inc_file" unless open I, "$ext_dir/$inc_file";
      $inc_it = 1;
    }
    elsif(
      (/^((\S*)|TEMPLATE([^:]*)):\s*(\S+)?\s*$/ && (my $t = $3, my $p = $2, my $s = $4, 1)) ||
      !defined($current_pack)
    ) {
      undef $current_pack;

      if(defined $t) {
        $p = '';
      }
      elsif($p eq 'TEMPLATE') {
        $p = '';
        $t = '';
      }

      if(defined $t) {
        $t =~ s/^\s*|\s*$//g;
        $t = ".*" if $t eq "";
      }

      my $auto_deps = 0;
      if($p eq 'AUTODEPS') {
        $p = '';
        $auto_deps = 1;
      }

      if($p =~ s/^\?// && !RealRPM($p)) {
        print "skipping package $p\n";
        next;
      }

      next unless defined $p;

      push @$packs, { name => '' };

      if(defined $s) {
        my @tags = split /,/, $s;

        @tags = grep { /^(requires|nodeps|ignore|direct)$/ } @tags;

        @{$packs->[-1]{tags}}{@tags} = ();
      }

      if(defined $t) {
        # is template, not real package
        $packs->[-1]{template} = $t;
        $packs->[-1]{template_index} = ++$template_cnt;

        print "adding template #$template_cnt >$t<\n";
      }

      if($auto_deps) {
        # also not real package
        $packs->[-1]{autodeps} = 1;
      }

      if($p eq '') {
        $current_pack = '';
        next;
      }

      # don't read ignored packages
      if(!exists $packs->[-1]{tags}{ignore} || $p =~ /\*\~/) {
        $rpm_dir = ReadRPM $p;

        next unless $rpm_dir;

        $rpm_file = $rpm_dir;
        $rpm_file =~ s#(/[^/]+)$#/.rpms$1.rpm#;

        $packs->[-1]{name} = RealRPM($p)->{name};
        $packs->[-1]{version} = ReadFile "$rpm_dir/version";

        $_ = ReadFile "$rpm_dir/scripts";
        if($_ ne "") {
          $packs->[-1]{all_scripts} = $_;
          my @scripts = split /,/;
          @{$packs->[-1]{scripts}}{@scripts} = ();

          my $update_links = parse_alternatives "$rpm_dir/postin";
          $packs->[-1]{alternatives} = $update_links if $update_links;
        }
      }
      else {
        ($packs->[-1]{name} = $p) =~ s/^\?//;
      }

      $current_pack = $packs->[-1]{name};

      my $ver = " [$packs->[-1]{version}]" if defined $packs->[-1]{version};
      my $all_scripts = $packs->[-1]{all_scripts};
      $ver .= " {$all_scripts}" if $all_scripts ne "";
    
      print "we " . (exists $packs->[-1]{tags}{ignore} ? "ignore" : "need") . " package $current_pack$ver\n";

      if(exists $packs->[-1]{tags}{requires}) {
        $_ = ReadFile "$rpm_dir/requires";
        open R, ">$dir/$p.requires";
        print R $_;
        close R;
      }

      $packs->[-1]{rpmdir} = $rpm_dir;
    }
    elsif(/^add_all\s+(\S+):$/) {
      my $pattern = $1;
      my $rpms = RealRPMs $pattern;
      print "add_all: $pattern = (", join(", ", @$rpms), ")\n";
      for my $p (@$rpms) {
        my $rpm_dir = ReadRPM $p;

        next unless $rpm_dir;

        my $entry = {};
        $entry->{name} = RealRPM($p)->{name};
        $entry->{version} = ReadFile "$rpm_dir/version";
        $entry->{rpmdir} = $rpm_dir;

        push @$packs, $entry;
      }
    }
    else {
      push @{$packs->[-1]{tasks}}, { src => $src_line, line => $_ };
    }
  }

  close F;

  # strip off templates
  $templates = [ grep { defined $_->{template} } @$packs ];
  $packs = [ grep { ! defined $_->{template} } @$packs ];

  # print Dumper $packs;
  # print Dumper $templates;

  # apply templates
  for my $t (@$templates) {
    for my $p (@$packs) {
      next if defined $p->{tasks};
      next if $p->{name} eq '';		# don't apply to empty names
      if($p->{name} =~ /^($t->{template})$/) {
        $p->{tasks} = $t->{tasks};
        for my $tag (keys %{$t->{tags}}) {
          $p->{tags}{$tag} = $t->{tags}{$tag};
        }
        $p->{from_template} = $t->{template_index};
      }
    }
  }

  # print Dumper $packs;

  my $auto_deps = (grep { $_->{autodeps} } @$packs)[0];

  if(defined $auto_deps) {
    $auto_deps->{packages} = find_missing_packs $packs;

    open my $f, ">${dir}.autodeps";
    for (sort keys %{$auto_deps->{packages}}) {
      print $f "$_ ($auto_deps->{packages}{$_})\n";
    }
    close $f;
  }

  # print Dumper $packs;

  # we're done parsing; now really add packages
  for (@$packs) {
    add_pack $dir, $ext_dir, $_;
  }

  my $tfile = "${TmpBase}.afile";
  SUSystem "rm -f $tfile";

  # print Dumper($used_packs);

  open my $l, ">${dir}.rpmlog";
  for (sort keys %$used_packs) {
    $_ = $used_packs->{$_};
    my $by = $_->{needed_by};
    if(defined $by) {
      if($by =~ s/^.*?< //) {
        $by = " < $by";
      }
      else {
        $by = '';
      }
    }
    print $l "$_->{name} [$_->{version}]$by\n";
  }
  close $l;

  $SIG{'__WARN__'} = $old_warn;

  return 1;
}


# - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - -
# Add an RPM as specified in a *.file_list file.
#
# add_pack(dir, ext_dir, package)
#
# dir: target directory
# ext_dir: directory extra data (data not in the rpm, cf. 'x' command in
#   *.file_list) is taken from
# package: package to install; this is the hash reference as returned by
#   RealRPM(), not just the rpm name
#
# Note: the difference to _add_pack() is that this function takes package
# dependencies into account (and calls _add_pack() as needed).
#
sub add_pack
{
  local $_;
  my $dir = shift;
  my $ext_dir = shift;
  my $pack = shift;

  return if exists $pack->{tags}{ignore};

  if(!defined $pack->{packages}) {
    _add_pack $dir, $ext_dir, $pack;
    return;
  }

  my $packages = $pack->{packages};

  for my $p (sort keys %$packages) {
    my $new_pack = {};

    $new_pack->{tasks} = $pack->{tasks} if defined $pack->{tasks};

    for my $tag (keys %{$pack->{tags}}) {
      $new_pack->{tags}{$tag} = $pack->{tags}{$tag};
    }

    my $rpm_dir = ReadRPM $p;

    next unless $rpm_dir;

    my $rpm_file = $rpm_dir;
    $rpm_file =~ s#(/[^/]+)$#/.rpms$1.rpm#;

    $new_pack->{name} = RealRPM($p)->{name};

    $new_pack->{version} = ReadFile "$rpm_dir/version";

    $new_pack->{all_scripts} = ReadFile "$rpm_dir/scripts";
    my @scripts = split /,/, $new_pack->{all_scripts};
    @{$new_pack->{scripts}}{@scripts} = ();

    my $update_links = parse_alternatives "$rpm_dir/postin";
    $new_pack->{alternatives} = $update_links if $update_links;

    if(exists $pack->{tags}{requires}) {
      $_ = ReadFile "$rpm_dir/requires";
      open R, ">$dir/$p.requires";
      print R $_;
      close R;
    }

    $new_pack->{rpmdir} = $rpm_dir;

    $new_pack->{needed_by} = $packages->{$p};

    # print "new = ", Dumper($new_pack);

    # apply templates
    if(!defined $new_pack->{tasks}) {
      for my $t (@$templates) {
        if($new_pack->{name} =~ /^($t->{template})$/) {
          $new_pack->{tasks} = $t->{tasks};
          for my $tag (keys %{$t->{tags}}) {
            $new_pack->{tags}{$tag} = $t->{tags}{$tag};
          }
          $new_pack->{from_template} = $t->{template_index};
          last;
        }
      }
    }

    # print "pack $p = ", Dumper($new_pack);

    _add_pack $dir, $ext_dir, $new_pack;
  }
}


# - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - -
# Add a single RPM as specified in a *.file_list file.
#
# _add_pack(dir, ext_dir, package)
#
# dir: target directory
# ext_dir: directory extra data (data not in the rpm, cf. 'x' command in
#   *.file_list) is taken from
# package: package to install; this is the hash reference as returned by
#   RealRPM(), not just the rpm name
#
# Note: do not call this function directly but use add_pack() instead.
#
sub _add_pack
{
  local $_;
  my $dir = shift;
  my $ext_dir = shift;
  my $pack = shift;

  return if exists $pack->{tags}{ignore};

  return unless defined $pack->{tasks} || exists $pack->{tags}{direct};

  my $tfile = "${TmpBase}.afile";

  my $tdir = "$pack->{rpmdir}/rpm";

  my $all_scripts = $pack->{all_scripts};
  $all_scripts = " {$all_scripts}" if $all_scripts ne "";

  my $t = "";
  $t = " using template #$pack->{from_template}" if defined $pack->{from_template};

  my $by = $pack->{needed_by};
  if(defined $by) {
    if($by =~ s/^.*?< //) {
      $by = " (< $by)";
    }
    else {
      $by = '';
    }
  }

  my $rpm_file;

  if($pack->{name} ne '') {
    $rpm_file = "$ConfigData{tmp_cache_dir}/.rpms/$pack->{name}.rpm";

    if(exists $pack->{tags}{direct}) {
      print "installing package $pack->{name} [$pack->{version}]$all_scripts$by\n";
      die "$rpm_file: rpm file missing" unless -r $rpm_file;
      my $abs_dir = File::Spec->rel2abs($dir);
      my $err = SUSystem "rpm -i --quiet --nosignature --nodeps --root '$abs_dir' --dbpath /instsys.xxx --rcfile /dev/null '$rpm_file'";
      SUSystem "rm -rf '$abs_dir/instsys.xxx'";
      warn "$Script: failed to install $pack->{name}" if $err;
    }
    else {
      print "adding package $pack->{name} [$pack->{version}]$all_scripts$by$t\n";
    }

    $used_packs->{$pack->{name}} = $pack;
  }

  for my $t (@{$pack->{tasks}}) {
    $_ = $t->{line};
    $src_line = $t->{src};

    if(!/^[a-zA-Z]\s+/) {
      # if rpm has been used to install the package all files are already there
      next if exists $pack->{tags}{direct};

      if($pack->{rpmdir} eq "") {
        warn "$Script: no package dir";
        next;
      }
      my $files = $_;
      $files =~ s.(^|\s)/.$1.g;
      $files = "." if $files =~ /^\s*$/;
      SUSystem "sh -c '( cd $tdir; tar --sparse -cf - $files 2>$tfile ) | tar --keep-directory-symlink -C $dir -xpf -'" and
        warn "$Script: failed to copy $files";

      my (@f, $f);
      @f = `cat $tfile`;
      print STDERR @f;
      SUSystem "rm -f $tfile";
      for $f (@f) {
        warn "$Script: failed to copy \"$files\"" if $f =~ /tar:\s+Error/;
      }
    }
    elsif(/^d\s+(.+)$/) {
      my $d = $1; $d =~ s.(^|\s)/.$1.g;
      SUSystem "sh -c 'cd $dir; mkdir -p $d'" and
        warn "$Script: failed to create $d";
    }
    elsif(/^t\s+(.+)$/) {
      my $d = $1; $d =~ s.(^|\s)/.$1.g;
      SUSystem "sh -c 'cd $dir; touch $d'" and
        warn "$Script: failed to touch $d";
    }
    elsif(/^r\s+(.+)$/) {
      my $d = $1; $d =~ s.(^|\s)/.$1.g;
      SUSystem "sh -c 'cd $dir; rm -rf $d'" and
        warn "$Script: failed to remove $d";
    }
    elsif(/^S\s+(.+)$/) {
      my $d = $1; $d =~ s.(^|\s)/.$1.g;
      SUSystem "sh -c 'cd $dir; strip $d'" and
        warn "$Script: failed to strip $d";
    }
    elsif(/^l\s+(\S+)\s+(\S+)$/) {
      SUSystem "ln $dir/$1 $dir/$2" and
        warn "$Script: failed to link $1 to $2";
    }
    elsif(/^s\s+(\S+)\s+(\S+)$/) {
      SUSystem "ln -sf $1 $dir/$2" and
        warn "$Script: failed to symlink $1 to $2";
    }
    elsif(/^D\s+(\S+)\s+\/?(\S+?)$/) {
      $dangling_links->{$2} = $1;
    }
    elsif(/^m\s+(\S+)\s+(\S+)$/) {
      SUSystem "sh -c \"cp -a $tdir/$1 $dir/$2\"" and
        warn "$Script: failed to move $1 to $2";
    }
    elsif(/^L\s+(\S+)\s+(\S+)$/) {
      SUSystem "sh -c \"cp -al $tdir/$1 $dir/$2\"" and
        warn "$Script: failed to move $1 to $2";
    }
    elsif(/^a\s+(\S+)\s+(\S+)$/) {
      SUSystem "sh -c \"cp -pLR $tdir/$1 $dir/$2\"" and
        warn "$Script: failed to move $1 to $2\n";
    }
    elsif(/^([fF])\s+(\S+)\s+(\S+)(\s+(\S+))?$/) {
      my ($l, @l, $src, $name, $dst, $start_dir);

      $src = $2;
      $name = $3;
      $dst = $5;
      $start_dir = $1 eq "F" ? "/" : $tdir;
      $src =~ s#^/*##;
      SUSystem "sh -c \"cd $start_dir ; find $src -type f -name '$name'\" >$tfile";

      open F1, "$tfile";
      @l = (<F1>);
      close F1;
      SUSystem "rm -f $tfile";
      chomp @l;

      if(@l == 0) {
        warn "$Script: \"$name\" not found in \"$src\"";
      }

      if($dst) {
        for $l (@l) {
          SUSystem "sh -c \"cp -a $start_dir/$l $dir/$dst\"" and
            print "$Script: $l not copied to $dst (ignored)\n";
        }
      }
      else {
        for $l (@l) {
          SUSystem "sh -c '( cd $start_dir; tar -cf - $l 2>$tfile ) | tar --keep-directory-symlink -C $dir -xpf -'" and
            warn "$Script: failed to copy files";

          my (@f, $f);
          @f = `cat $tfile`;
          print STDERR @f;
          SUSystem "rm -f $tfile";
          for $f (@f) {
            warn "$Script: failed to copy \"$l\"" if $f =~ /tar:\s+Error/;
          }
        }
      }
    }
    elsif(/^p\s+(\S+)$/) {
      SUSystem "patch -d $dir -p0 --no-backup-if-mismatch <$ext_dir/$1" and
        warn "$Script: failed to apply patch $1";
    }
    elsif(/^P\s+(\S+)$/) {
      if($rpm_file && -r $rpm_file) {
        SUSystem "cp -L $rpm_file $dir/$1 2>/dev/null" and
          warn "$Script: failed to copy rpm to $1";
      }
      else {
        warn "$Script: no package file";
      }
    }
    elsif(/^A\s+(\S+)\s+(\S+)$/) {
      SUSystem "sh -c 'cat $ext_dir/$1 >>$dir/$2'" and
        warn "$Script: failed to append $1 to $2";
    }
    elsif(/^x\s+(\S+)\s+(\S+)$/) {
      SUSystem "cp -dR $ext_dir/$1 $dir/$2" and
        warn "$Script: failed to move $1 to $2";
    }
    elsif(/^X\s+(\S+)\s+(\S+)$/) {
      SUSystem "cp -Lpr $1 $dir/$2 2>/dev/null" and
        print "$Script: $1 not copied to $2 (ignored)\n";
    }
    elsif(/^g\s+(\S+)\s+(\S+)$/) {
      SUSystem "sh -c 'gunzip -c $tdir/$1 >$dir/$2'" and
        warn "$Script: could not uncompress $1 to $2";
    }
    elsif(/^c\s+(\d+)\s+(\S+)\s+(\S+)\s+(.+)$/) {
      my $p = $1; my $u = $2; my $g = $3;
      my $d = $4; $d =~ s.(^|\s)/.$1.g;
      SUSystem "sh -c 'cd $dir; chown $u:$g $d'" and
        warn "$Script: failto to change owner of $d to $u:$g";
      SUSystem "sh -c 'cd $dir; chmod $p $d'" and
        warn "$Script: failto to change perms of $d to $p";
    }
    elsif(/^b\s+(\d+)\s+(\d+)\s+(\S+)$/) {
      SUSystem "mknod $dir/$3 b $1 $2" and
        warn "$Script: failto to make block dev $3 ($1, $2)";
    }
    elsif(/^C\s+(\d+)\s+(\d+)\s+(\S+)$/) {
      SUSystem "mknod $dir/$3 c $1 $2" and
        warn "$Script: failto to make char dev $3 ($1, $2)";
    }
    elsif(/^n\s+(.+)$/) {
      SUSystem "mknod $dir/$1 p" and
        warn "$Script: failto to make named pipe $1";
    }
    elsif(/^([eE])\s+(.+)$/) {
      my ($cmd, $xdir, $basedir, $r, $e, $pm, $is_script);

      $e = $1;
      $cmd = $2;
      $xdir = $dir;
      $xdir =~ s#/*$##;
      $basedir = $1 if $xdir =~ s#(.*)/##;
      $is_script = exists $pack->{scripts}{$cmd};
      $pm = $is_script ? "$cmd script" : "\"$cmd\"";

      die "internal oops" unless $basedir ne "" && $xdir ne "";

      if($is_script) {
        SUSystem "sh -c 'mkdir $dir/install && chmod 777 $dir/install'" and
          die "$Script: failed to create $dir/install";
        system "cp $pack->{rpmdir}/$cmd $dir/install/inst.sh" and die "$Script: unable to create $pm";

        $e = 'E' if $xdir eq 'base';
      }

      print "running $pm\n";

      if($e eq 'e') {
        SUSystem "mv $dir $basedir/base/xxxx" and die "oops";

        # cf. bsc#1176972
        mount_proc_and_stuff("$basedir/base");

        if($is_script) {
          $r = SUSystem "chroot $basedir/base /bin/sh -c 'cd xxxx ; sh install/inst.sh 1'";
        }
        else {
          $r = SUSystem "chroot $basedir/base /bin/sh -c 'cd xxxx ; $cmd'";
        }

        umount_proc_and_stuff("$basedir/base");

        SUSystem "mv $basedir/base/xxxx $dir" and die "oops";
      }
      else {
        # cf. bsc#1160594
        mount_proc_and_stuff($dir);

        if($is_script) {
          $r = SUSystem "chroot $dir /bin/sh -c 'sh install/inst.sh 1'";
        }
        else {
          $r = SUSystem "chroot $dir /bin/sh -c '$cmd'";
        }

        umount_proc_and_stuff($dir);
      }
      warn "$Script: execution of $pm failed" if $r;

      SUSystem "rm -rf $dir/install" if $is_script;
    }
    elsif(/^R\s+(.+?)\s+(\S+)$/) {
      my ($file, $re, @f, $i);

      $file = $2;
      $re = $1 . '; 1';		# fixup_re($1) ?

      # die "$Script: $file: no such file" unless -f "$dir/$file";
      system "touch $tfile" and die "unable to access $file";
      SUSystem "cp $dir/$file $tfile" and die "unable to access $file";

      die "$Script: $file: $!" unless open F1, "$tfile";
      @f = (<F1>);
      close F1;
      SUSystem "rm -f $tfile";

      if($re =~ /\/sg?; 1$/) {	# multi line
        $_ = join '', @f;
        $ignore += 10;
        $i = eval $re;
        $ignore -= 10;
        die "$Script: syntax error in expression" unless defined $i;
        @f = ( $_ );
      }
      else {
        for (@f) {
          $ignore += 10;
          $i = eval $re;
          $ignore -= 10;
          die "$Script: syntax error in expression" unless defined $i;
        }
      }
      die "$Script: $file: $!" unless open F1, ">$tfile";
      print F1 @f;
      close F1;

      SUSystem "cp $tfile $dir/$file" and die "unable to access $file";
      SUSystem "rm -f $tfile";
    }
    else {
      die "$Script: unknown entry: \"$_\"\n";
    }
  }

  if($pack->{alternatives}) {
    print "-- update-alternative symlinks --\n";
    for my $l (sort keys %{$pack->{alternatives}}) {
      my $lt = $pack->{alternatives}{$l};
      if(-e "$dir/$lt" ) {
        print "  adding $l --> $lt\n";
        SUSystem "ln -sf $lt $dir/$l" and warn "$Script: failed to symlink $lt to $l";
      }
      else {
        print "  skipping $l --> $lt\n";
      }
    }
  }
}


# - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - -
sub find_missing_packs
{
  my $packs = shift;

  my $ignore;
  my $all;
  my $old;

  print "resolving package dependencies...\n";

  for (@$packs) {
    next if $_->{name} eq '';
    $all->{$_->{name}} = 1;
    $ignore->{$_->{name}} = 1 if exists $_->{tags}{ignore} || exists $_->{tags}{nodeps};
  }

  delete $all->{$_} for (keys %$ignore);

  if($old->{name} = $ENV{disjunct}) {
    $old->{dir} = $dir;
    $old->{dir} =~ s#[^/]+$#$old->{name}#;
    if(open my $f, "$old->{dir}.rpmlog") {
      my $p;
      while(<$f>) {
        $p = (split)[0];
        $old->{packs}{$p} = 1 if $p ne "";
      }
      close $f;
    }
    else {
      die "$old->{dir}.romlog: $old package list missing";
    }
    if(open my $f, "$old->{dir}.solv") {
      while(<$f>) {
        chomp;
        if(s/^\-//) {
          $old->{ignore}{$_} = 1;
        }
        else {
          $old->{all}{$_} = 1;
        }
      }
      close $f;
    }
    else {
      die "$old->{dir}.solv: $old package solv list missing";
    }
  }

  # print Dumper($old);

  for (keys %$all) {
    $old->{all}{$_} = 1;
    delete $old->{ignore}{$_};
  }

  for (keys %$ignore) {
    delete $old->{all}{$_};
    $old->{ignore}{$_} = 1;
  }

  $all = $old->{all};
  $ignore = $old->{ignore};

  if(open my $f, ">${dir}.solv") {
    print $f "$_\n" for sort keys %$all;
    print $f "-$_\n" for sort keys %$ignore;
    close $f;
  }

  my $r = ResolveDeps [ keys %$all ], [ keys %$ignore ], $old->{packs};

  # print Dumper($r);

  return $r;
}


# - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - -
# Check if an rpm contains a file.
#
# rpm_has_file(rpm, file, type)
#
# If file is missing, verifies only existence of rpm.
# If type is specified, types must match.
#
# type is perl's -X operator (without the '-').
#
sub rpm_has_file
{
  my ($rpm, $file, $type) = @_;

  return 0 if !RealRPM $rpm;

  return 1 if $file eq "";

  my $rpm_dir = ReadRPM $rpm;

  return 0 if !$rpm_dir;

  $type = 'e' if !$type;

  return eval "-$type \"$rpm_dir/rpm/$file\"";
}


# - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - -
sub fixup_re
{
  local ($_);
  my ($re, $re0, $val);

  $re0 = $re = shift;
  $re0 =~ s/(('[^']*')|("[^"]*")|\b(defined|lt|gt|le|ge|eq|ne|cmp|not|and|or|xor)\b|(\(|\)))|\bexists\([^)]*\)/' ' x length($1)/ge;
  while($re0 =~ s/^((.*)(\b[a-zA-Z]\w+\b))/$2 . (' ' x length($3))/e) {
#    print "    >>$3<<\n";
    if(exists $ConfigData{$3}) {
      $val = "\$ConfigData{'$3'}";
    }
    else {
      $val = "\$ENV{'$3'}";
    }
    $val = $ENV{'___arch'} if $3 eq 'arch';
    substr($re, length($2), length($3)) = $val;
  }

  $re =~ s/\bexists\(([^),]+)(?:,\s*([^),]*))?(?:,\s*([^),]*))?\)/rpm_has_file($1, $2, $3) ? 1 : 0/eg;

  return $re;
}


# - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - -
# Look up a config variable and (if it exists) return the config variable's
# value.
#
# If the config variable does not exist log it and return (the literal
# string) "<$name>".
#
# Config variables are entries in the %ConfigData hash, possibly overridden
# by environment variables of the same name.
#
# replace_config_var(name)
#
sub replace_config_var
{
  my $name = $_[0];
  my $val;

  $val = $ConfigData{$name} if exists $ConfigData{$name};
  $val = $ENV{$name} if exists $ENV{$name};

  return $val if defined $val;

  print "undefined config var: $name\n";

  return "<$name>";
}


# - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - -
# Set up /proc and /dev/fd in directory dir if they are missing as a number
# of tools rely on these (bsc#1160594, bsc#1176972).
#
# This is necessary when you plan to chroot into this directory and run
# commands there.
#
# Each call to mount_proc_and_stuff must be undone by calling
# umount_proc_and_stuff for the same directory.
#
# mount_proc_and_stuff(dir)
#
sub mount_proc_and_stuff
{
  my $dir = $_[0];

  # no stacking or fancy stuff
  return if $mount_proc_state->{$dir};

  # remember current situation
  $mount_proc_state->{$dir}{proc} = -d "$dir/proc";
  $mount_proc_state->{$dir}{dev} = -d "$dir/dev";
  $mount_proc_state->{$dir}{fd} = -e "$dir/dev/fd";

  # create missing parts
  SUSystem("mkdir $dir/dev") if !$mount_proc_state->{$dir}{dev};
  SUSystem("ln -s /proc/self/fd $dir/dev/fd") if !$mount_proc_state->{$dir}{fd};
  SUSystem("mkdir $dir/proc") if !$mount_proc_state->{$dir}{proc};

  # mount proc fs
  SUSystem("mount -oro -t proc proc $dir/proc");
}


# - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - -
# Undo whatever mount_proc_and_stuff might have done.
#
# Each call to mount_proc_and_stuff() must be undone by calling
# umount_proc_and_stuff for the same directory.
#
# umount_proc_and_stuff(dir)
#
sub umount_proc_and_stuff
{
  my $dir = $_[0];

  return if !$mount_proc_state->{$dir};

  # umount proc fs
  SUSystem("umount $dir/proc");

  # remove added parts
  SUSystem("rmdir $dir/proc") if !$mount_proc_state->{$dir}{proc};
  SUSystem("rm $dir/dev/fd") if !$mount_proc_state->{$dir}{fd};
  SUSystem("rmdir $dir/dev") if !$mount_proc_state->{$dir}{dev};

  delete $mount_proc_state->{$dir};
}


# - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - -
# Parse package postinstall script for update-alternative calls.
#
# Return hash with symlinks or undef if update-alternative was not used.
#
# parse_alternatives(file)
#
sub parse_alternatives
{
  my $file = $_[0];

  my $update_links;
  my $update_lines;

  if(open my $f, $file) {
    my $update_cont;
    while(<$f>) {
      chomp;
      my $next_cont = s/\\$// ? 1 : 0;
      if($update_cont) {
        $update_lines->[-1] .= "$_";
      }
      elsif(/update-alternatives\s/) {
        push @$update_lines, $_;
      }
      else {
        next;
      }
      $update_cont = $next_cont;
    }
    close $f;
  }

  if($update_lines) {
    for (@$update_lines) {
      while(/--(?:install|slave)\s+(\S+)\s+(?:\S+)\s+(\S+)/g) {
        my $l = $1;
        my $lt = $2;
        $l =~ s/^(["'])(.*)\1$/$2/;
        $lt =~ s/^(["'])(.*)\1$/$2/;
        $update_links->{$l} = $lt;
      }
    }
  }

  return $update_links;
}

1;
