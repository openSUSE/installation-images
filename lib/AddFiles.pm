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
  my ($old_warn, $ver, $i, $cache_dir, $tmp_cache_dir, $tmp_rpm);
  my (@scripts, $s, @s, %script, $use_cache);
  my (@packs, $sl);

  ($dir, $file_list, $ext_dir, $tag, $mod_list) = @_;

  $debug = "pkg";
  $debug = $ENV{'debug'} if exists $ENV{'debug'};

  $use_cache = 0;
  $use_cache = $ENV{'cache'} if exists $ENV{'cache'};
  if($use_cache) {
    $cache_dir = $ConfigData{'cache_dir'};
    $tmp_cache_dir = $ConfigData{'tmp_cache_dir'};
  }

  $ignore = $debug =~ /\bignore\b/ ? 1 : 0;

  $old_warn =  $SIG{'__WARN__'};

  $SIG{'__WARN__'} = sub {
    my $a = shift;

    return if $ignore >= 10;

    $a =~ s/<F>/$file_list/;
    $a =~ s/<I>/$inc_file/;
    if($ignore) { warn $a } else { die $a }
  };

  $debug .= ',pkg';

#  if(!$AutoBuild) {
#    $rpms = "$ConfigData{suse_base}/suse";
#    die "$Script: where are the rpms?" unless $ConfigData{suse_base} && -d $rpms;
#    $rpms = "$rpms/*";
#  }
# else {
#    $rpms = $AutoBuild;
#    die "$Script: where are the rpms?" unless -d $rpms;
#    print "running in autobuild environment\n";
#  }

  if(! -d $dir) {
    die "$Script: failed to create $dir ($!)" unless mkdir $dir, 0755;
  }

  if(!($use_cache & 4)) {
    $tdir = "${TmpBase}.dir";
    die "$Script: failed to create $tdir ($!)" unless mkdir $tdir, 0777;
  }
  $tfile = "${TmpBase}.afile";

  # - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - -
  # now we really start...

  die "$Script: no such file list: $file_list" unless open F, $file_list;

  $arch = `uname -m`; chomp $arch;
  $arch = "ia32" if $arch =~ /^i\d86$/;

  $ENV{'___arch'} = $arch;

  $tag = "" unless defined $tag;

  $if_val = $if_taken = 0;

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

    s/<(kernel_ver|kernel_rpm|kernel_img|suse_release|theme|product|product_name|yast_theme|splash_theme|update_dir|load_image)>/$ConfigData{$1}/g;
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

# drop these
#    if(/^ifarch\s+/)  { $if_val <<= 1; $if_val |= 1 if !/\b$arch\b/ || $arch eq ""; next }
#    if(/^ifnarch\s+/) { $if_val <<= 1; $if_val |= 1 if  /\b$arch\b/ && $arch ne ""; next }
#    if(/^ifdef\s+/)   { $if_val <<= 1; $if_val |= 1 if !/\b$tag\b/  || $tag  eq ""; next }
#    if(/^ifndef\s+/)  { $if_val <<= 1; $if_val |= 1 if  /\b$tag\b/  && $tag  ne ""; next }
#    if(/^ifabuild/)   { $if_val <<= 1; $if_val |= 1 if !$AutoBuild;                 next }
#    if(/^ifnabuild/)  { $if_val <<= 1; $if_val |= 1 if  $AutoBuild;                 next }
#    if(/^ifenv\s+(\S+)\s+(\S+)/)  { $if_val <<= 1; $if_val |= 1 if $ENV{$1} ne $2;  next }
#    if(/^ifnenv\s+(\S+)\s+(\S+)/) { $if_val <<= 1; $if_val |= 1 if $ENV{$1} eq $2;  next }

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
    elsif(/^(\S+):\s*(\S+)?\s*$/) {
      undef %script;
      undef @scripts;

      $p = $1;
      if(defined $2) {
        @scripts = split /,/, $2;
      }

      undef $rc;
      undef $r;
      if($p =~ /^\//) {
        $r = $p;
        warn("$Script: no such package: $r"), next unless -f $r;
      }
      else {
        $r = RPMFileName $p;

        if($use_cache) {
          $rc = "$cache_dir/$p.rpm";
          $tmp_rpm = "$tmp_cache_dir/$p";
        }
        warn("$Script: no such package: $p.rpm"), next unless $r && -f $r;

        if(($use_cache & 2) && $rc && $r && -f($r) && $rc ne $r) {
          if(! -d($cache_dir)) {
            SUSystem("mkdir -p $cache_dir");
          }
          if(-d $cache_dir) {
            SUSystem("cp -a $r $rc");
            if(-f $rc) {
              $r = $rc;
            }
            else {
              warn "$Script: failed to cache package $r";
            }
          }
          else {
            warn "$Script: failed to create cache dir $cache_dir";
            $use_cache = 0;
          }
        }
      }

      $ver = (`rpm -qp $r`)[0];
      $ver = "" unless defined $ver;
      $ver =~ s/\s*$//;
      if($ver =~ /^(\S+)-([^-]+-[^-]+)$/) {
        $ver = $1 eq $p ? " [$2]" : "";
      }
      else {
        $ver = "";
      }
      if($use_cache) {
        if(-d $tmp_rpm) {
          $ver .= '#';
        }
        elsif(defined($rc) && $rc eq $r) {
          $ver .= '*';
        }
      }

      undef $sl;

      @s = `rpm -qp --qf '%|PREIN?{PREIN\n}:{}|%|POSTIN?{POSTIN\n}:{}|%|PREUN?{PREUN\n}:{}|%|POSTUN?{POSTUN\n}:{}|' $r 2>/dev/null`;
      for $s (@s) {
        chomp $s;
        $sl .= "," if $sl;
        $sl .= "\L$s";
      }
      $ver .= " \{$sl\}" if $sl;

      print "adding package $p$ver\n" if $debug =~ /\bpkg\b/;

      push @packs, "$p\n";

      for $s (@scripts) {
        @{$script{$s}} =
        @s = `rpm --queryformat '%{\U$s\E}' -qp $r 2>/dev/null`;
        if(@s == 0 || $s[0] =~ /^\(none\)\s*$/) {
          warn "$Script: no \"$s\" script in $r";
        }
        else {
          print "  got \"$s\" script\n" if $debug =~ /\bscripts\b/;
          @{$script{$s}} = @s;
        }
      }

      if(!($use_cache & 4)) {
        SUSystem "rm -rf $tdir" and die "$Script: failed to remove $tdir";
        die "$Script: failed to create $tdir ($!)" unless mkdir $tdir, 0777;
        SUSystem "sh -c 'cd $tdir ; rpm2cpio $r | cpio --quiet -dimu --no-absolute-filenames'" and
          warn "$Script: failed to extract $r";
      }
      else {
        $tdir = $tmp_rpm;
        if(!-d($tdir)) {
          die "$Script: failed to create $tdir ($!)" unless mkdir $tdir, 0777;
          SUSystem "sh -c 'cd $tdir ; rpm2cpio $r | cpio --quiet -dimu --no-absolute-filenames'" and
            warn "$Script: failed to extract $r";
        }
      }
    }
    elsif(!/^[a-zA-Z]\s+/ && /^(.*)$/) {
      $files = $1;
      $files =~ s.(^|\s)/.$1.g;
      $files = "." if $files =~ /^\s*$/;
      SUSystem "sh -c '( cd $tdir; tar -cf - $files 2>$tfile ) | tar -C $dir -xpf -'" and
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
      SUSystem "patch -d $dir -p0 --no-backup-if-mismatch <$ext_dir/$1 >/dev/null" and
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
      SUSystem "cp -dR $1 $dir/$2 2>/dev/null" and
        print "$Script: $1 not copied to $2 (ignored)\n";
    }
    elsif(/^g\s+(\S+)\s+(\S+)$/) {
      SUSystem "sh -c 'gunzip -c $tdir/$1 >$dir/$2'" and
        warn "$Script: could not uncompress $1 to $2";
    }
    elsif(/^c\s+(\d+)\s+(\S+)\s+(\S+)\s+(.+)$/) {
      $p = $1; $u = $2; $g = $3;
      $d = $4; $d =~ s.(^|\s)/.$1.g;
      SUSystem "sh -c 'cd $dir; chown $u.$g $d'" and
        warn "$Script: failto to change owner of $d to $u.$g";
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
        print W @{$script{$cmd}};
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

      die "$Script: $file: no such file" unless -f "$dir/$file";
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

  if(!($use_cache & 4)) {
    SUSystem "rm -rf $tdir";
  }
  SUSystem "rm -f $tfile";

  open F, ">${dir}.rpms";
  print F @packs;
  close F;

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
  $re0 =~ s/(('[^']*')|("[^"]*")|\b(defined|lt|gt|le|ge|eq|ne|cmp|not|and|or|xor)\b|(\(|\)))/' ' x length($1)/ge;
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

  return $re;
}


1;
