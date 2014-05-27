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

sub add_pack;
sub _add_pack;
sub find_missing_packs;
sub fixup_re;

my $ignore;
my $src_line;
my $templates;
my $used_packs;
my $dangling_links;


# - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - -
sub AddFiles
{
  local $_;

  my ($dir, $file_list, $ext_dir, $arch, $if_val, $if_taken);
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
    s/<(kernel_ver|kernel_mods|kernel_rpm|kernel_img|(suse|sles|sled)_release|theme|base_theme|splash_theme|yast_theme|product|product_name|update_dir|load_image|min_memory|instsys_build_id|instsys_complain|instsys_complain_root|arch|lib)>/$ConfigData{$1}/g;
    for my $i (qw( linuxrc lang extramod items )) {
      s/<$i>/$ENV{$i}/g if exists $ENV{$i};
    }

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

        @tags = grep { /^(requires|nodeps|ignore)$/ } @tags;

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

  open my $f, ">${dir}.rpms";
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
    print $f "$_->{name}\n";
    print $l "$_->{name} [$_->{version}]$by\n";
  }
  close $f;
  close $l;

  $SIG{'__WARN__'} = $old_warn;

  return 1;
}


# - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - -
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
sub _add_pack
{
  local $_;
  my $dir = shift;
  my $ext_dir = shift;
  my $pack = shift;

  return if exists $pack->{tags}{ignore};

  return if !defined $pack->{tasks};

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

  if($pack->{name} ne '') {
    print "adding package $pack->{name} [$pack->{version}]$all_scripts$by$t\n";
    $used_packs->{$pack->{name}} = $pack;
  }

  for my $t (@{$pack->{tasks}}) {
    $_ = $t->{line};
    $src_line = $t->{src};

    if(!/^[a-zA-Z]\s+/) {
      if($pack->{rpmdir} eq "") {
        warn "$Script: no package dir";
        next;
      }
      my $files = $_;
      $files =~ s.(^|\s)/.$1.g;
      $files = "." if $files =~ /^\s*$/;
      SUSystem "sh -c '( cd $tdir; tar --sparse -cf - $files 2>$tfile ) | tar -C $dir -xpf -'" and
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
          SUSystem "sh -c '( cd $start_dir; tar -cf - $l 2>$tfile ) | tar -C $dir -xpf -'" and
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
        if($is_script) {
          $r = SUSystem "chroot $basedir/base /bin/sh -c 'cd xxxx ; sh install/inst.sh 1'";
        }
        else {
          $r = SUSystem "chroot $basedir/base /bin/sh -c 'cd xxxx ; $cmd'";
        }
        SUSystem "mv $basedir/base/xxxx $dir" and die "oops";
      }
      else {
        if($is_script) {
          $r = SUSystem "chroot $dir /bin/sh -c 'sh install/inst.sh 1'";
        }
        else {
          $r = SUSystem "chroot $dir /bin/sh -c '$cmd'";
        }
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

      if($re =~ /\/s; 1$/) {	# multi line
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
}


# - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - -
sub find_missing_packs
{
  my $packs = shift;

  my $ignore;
  my $all;

  print "resolving package dependencies...\n";

  for (@$packs) {
    next if $_->{name} eq '';
    $all->{$_->{name}} = 1;
    $ignore->{$_->{name}} = 1 if exists $_->{tags}{ignore} || exists $_->{tags}{nodeps};
  }

  delete $all->{$_} for (keys %$ignore);

  my $r = ResolveDeps [ keys %$all ], [ keys %$ignore ];

  # print Dumper($r);

  return $r;
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

  $re =~ s/\bexists\(([^)]*)\)/RealRPM($1) ? 1 : 0/eg;

  return $re;
}


1;
