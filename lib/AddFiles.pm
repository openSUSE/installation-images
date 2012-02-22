#! /usr/bin/perl -w

# Usage:
#
#   use AddFiles;
#
#   exported functions:
#     AddFiles(dir, file_list, ext_dir, tag);

=head1 AddFiles

C<AddFiles.pm> is a perl module that can be used to extract files from
rpms. It exports the following symbols:

=over

=item *

C<AddFiles(dir, file_list, ext_dir, tag)>

=back

=head2 Usage

use AddFiles;

=head2 Description

=over

=item *

C<AddFiles(dir, file_list, ext_dir, tag)>

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

use ReadConfig;

sub fixup_re;


sub AddFiles
{
  local $_;
  my ($dir, $file_list, $ext_dir, $arch, $if_val, $if_taken, $tag);
  my ($rpms, $tdir, $tfile, $p, $r, $rc, $d, $u, $g, $files);
  my ($mod_list, @mod_list, %mod_list);
  my ($inc_file, $inc_it, $debug, $ifmsg, $ignore);
  my ($old_warn, $ver, $i);
  my (@scripts, $s, @s, %script);
  my (@packs, $sl, $rpm_dir, $rpm_file);
  my (@plog, $current_pack, %acc_all_files, %acc_pack_files, $account);
  my ($su, @requires);

  $su = "$SUBinary -q 0 " if $SUBinary;

  my $account_size = sub
  {
    my ($dir, $s, @f);
    local $_;

    return if !defined($current_pack) || !$account;

    $dir = shift;

    @f = `${su}find $dir -type f`;

    chomp @f;

    for (@f) {
      $acc_pack_files{$current_pack}{$_} = 1 unless exists $acc_all_files{$_};
      $acc_all_files{$_} = 1;
    }
  };

  ($dir, $file_list, $ext_dir, $tag, $mod_list) = @_;

  $debug = "pkg";
  $debug = $ENV{'debug'} if exists $ENV{'debug'};

  $ignore = $debug =~ /\bignore\b/ ? 1 : 0;

  $account = $debug =~ /\baccount\b/ ? 1 : 0;

  $old_warn =  $SIG{'__WARN__'};

  $SIG{'__WARN__'} = sub {
    my $a = shift;

    return if $ignore >= 10;

    $a =~ s/<F>/$file_list/;
    $a =~ s/<I>/$inc_file/;
    if($ignore) { warn $a } else { die $a }
  };

  $debug .= ',pkg';

  if(! -d $dir) {
    die "$Script: failed to create $dir ($!)" unless mkdir $dir, 0755;
  }

  $tfile = "${TmpBase}.afile";

  # - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - -
  # now we really start...

  die "$Script: no such file list: $file_list" unless open F, $file_list;

  $arch = $ConfigData{arch};
  $ENV{'___arch'} = $arch;

  $tag = "" unless defined $tag;

  $if_val = $if_taken = 0;

  $current_pack = '';

  while(1) {
    $_ = $inc_it ? <I> : <F>;
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

    $ifmsg = sprintf " [%x|%x] %s\n", $if_val, $if_taken, $_;

    s/<rpm_file>/$rpm_file/g;
    s/<(kernel_ver|kernel_mods|kernel_rpm|kernel_img|(suse|sles|sled)_release|theme|splash_theme|yast_theme|product|product_name|update_dir|load_image|min_memory|instsys_build_id|instsys_complain|instsys_complain_root|arch|lib)>/$ConfigData{$1}/g;
    for $i (qw( linuxrc lang extramod items )) {
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
        $i = 0 if $i == 0 && ($if_taken & 1) == 0;
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
    elsif(/^(\S*):\s*(\S+)?\s*$/ || !defined($current_pack)) {
      undef %script;
      undef @scripts;
      undef @requires;

      $account_size->($dir);

      undef $current_pack;

      $p = $1;
      my $s = $2;

      if($p =~ s/^\?// && !RealRPM($p)) {
        print "skipping package $p\n";
        next;
      }

      if(defined $s) {
        @scripts = split /,/, $s;

        @requires = grep { $_ eq 'requires' } @scripts;
        @scripts = grep { $_ ne 'requires' } @scripts;
      }

      next unless defined $p;

      if($p eq '') {
        $current_pack = '';
        next;
      }

      undef $rc;
      undef $r;

      $rpm_dir = ReadRPM $p;

      next unless $rpm_dir;

      $rpm_file = $rpm_dir;
      $rpm_file =~ s#(/[^/]+)$#/.rpms$1.rpm#;

      $current_pack = RealRPM($p)->{name};

      $ver = ReadFile "$rpm_dir/version";
      $ver = "[$ver]";

      push @plog, "$current_pack $ver\n";

      $_ = ReadFile "$rpm_dir/scripts";
      $ver .= " {$_}" if $_;

      print "adding package $current_pack $ver\n" if $debug =~ /\bpkg\b/;

      push @packs, "$current_pack\n";

      for $s (@scripts) {
        $_ = ReadFile "$rpm_dir/$s";
        if(!$_) {
          warn "$Script: no \"$s\" script in $current_pack";
        }
        else {
          print "  got \"$s\" script\n" if $debug =~ /\bscripts\b/;
          $script{$s} = $_;
        }
      }

      if(@requires) {
        $_ = ReadFile "$rpm_dir/requires";
        open R, ">$dir/$p.requires";
        print R $_;
        close R;
      }

      $tdir = "$rpm_dir/rpm";
    }
    elsif(!/^[a-zA-Z]\s+/ && /^(.*)$/) {
      $files = $1;
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
      $d = $1; $d =~ s.(^|\s)/.$1.g;
      SUSystem "sh -c 'cd $dir; mkdir -p $d'" and
        warn "$Script: failed to create $d";
    }
    elsif(/^t\s+(.+)$/) {
      $d = $1; $d =~ s.(^|\s)/.$1.g;
      SUSystem "sh -c 'cd $dir; touch $d'" and
        warn "$Script: failed to touch $d";
    }
    elsif(/^r\s+(.+)$/) {
      $d = $1; $d =~ s.(^|\s)/.$1.g;
      SUSystem "sh -c 'cd $dir; rm -rf $d'" and
        warn "$Script: failed to remove $d";
    }
    elsif(/^S\s+(.+)$/) {
      $d = $1; $d =~ s.(^|\s)/.$1.g;
      SUSystem "sh -c 'cd $dir; strip $d'" and
        warn "$Script: failed to strip $d";
    }
    elsif(/^l\s+(\S+)\s+(\S+)$/) {
      SUSystem "ln $dir/$1 $dir/$2" and
        warn "$Script: failed to link $1 to $2";
    }
    elsif(/^s\s+(\S+)\s+(\S+)$/) {
      SUSystem "ln -s $1 $dir/$2" and
        warn "$Script: failed to symlink $1 to $2";
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
            warn "$Script: failed to copy $files";

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
      $p = $1; $u = $2; $g = $3;
      $d = $4; $d =~ s.(^|\s)/.$1.g;
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
=head1
    elsif(/^M\s+(\S+)\s+(\S+)$/) {
      SUSystem "sh -c \"cp -av $tdir/$1 $dir/$2\" >$tfile" and
        print "$Script: $1 not copied to $2 (ignored)\n";

      my ($f, $g);
      for $f (`cat $tfile`) {
        if($f =~ /\s->\s$dir\/(.*)\n?$/) {
          $g = $1; $g =~ s/^\/*//;
          push @mod_list, "$g\n" unless exists $mod_list{$g};
          $mod_list{$g} = 1;
        }
        elsif($f =~ /\s->\s\`$dir\/(.*)\'\n?$/) {
          $g = $1; $g =~ s/^\/*//;
          push @mod_list, "$g\n" unless exists $mod_list{$g};
          $mod_list{$g} = 1;
        }
      }
    }
=cut
    elsif(/^M\s+(.*)$/) {
      my ($ml, @ml);

      $ml = $1;
      @ml = split ' ', $ml;
      if($ml !~ m#/#) {
        @ml = map { $_ = "modules/$_.o\n" } @ml;
      }
      else {
        @ml = map { $_ .= "\n" } @ml;
      }
      push @mod_list, @ml
    }
    elsif(/^([eE])\s+(.+)$/) {
      my ($cmd, $xdir, $basedir, $r, $e, $pm, $is_script);

      $e = $1;
      $cmd = $2;
      $xdir = $dir;
      $xdir =~ s#/*$##;
      $basedir = $1 if $xdir =~ s#(.*)/##;
      $is_script = exists $script{$cmd};
      $pm = $is_script ? "$cmd script" : "\"$cmd\"";

      die "internal oops" unless $basedir ne "" && $xdir ne "";

      if($is_script) {
        SUSystem "sh -c 'mkdir $dir/install && chmod 777 $dir/install'" and
          die "$Script: failed to create $dir/install";
        die "$Script: unable to create $pm" unless open W, ">$dir/install/inst.sh";
        print W $script{$cmd};
        close W;

        $e = 'E' if $xdir eq 'base';
      }

      print "running $pm\n" if $debug =~ /\bpkg\b/;
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

  close F;

  $account_size->($dir);

  SUSystem "rm -f $tfile";

  open F, ">${dir}.rpms";
  print F @packs;
  close F;

  open F, ">${dir}.rpmlog";
  print F @plog;
  close F;

  if(%acc_pack_files) {
    open F, ">${dir}.size";
    for $p (sort keys %acc_pack_files) {
      # print "$p:\n";
      my $size = 0;
      my $s = 0;
      for (keys %{$acc_pack_files{$p}}) {
        $size += (split ' ', `${su}du -bsk $_ 2>/dev/null`)[0];
        # print "$_: $size\n";
      }
      printf F "%-24s %s\n", $p eq '' ? 'no package' : $p, $size;
    }
    close F;
  }

  if($ENV{'nomods'}) {
    for (split /,/, $ENV{'nomods'}) {
      push @mod_list, "modules/$_.o\n"
    }
  }

  if(@mod_list && $mod_list) {
    open F, ">$mod_list";
    print F @mod_list;
    close F;
  }

  $SIG{'__WARN__'} = $old_warn;

  return 1;
}


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
