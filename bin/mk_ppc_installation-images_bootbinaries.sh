#!/bin/bash
# $Id$
# usage: $0 [-32] [-64] <bdir> <targetdirectory>
set -ex

do_32=false
do_64=false
do_bits=
i=

until test "$#" = 0
do
	echo "\$1 '$1'"
	case "$1" in
		-32) do_32=true ; shift;;
		-64) do_64=true ; shift;;
		*)   break ;;
	esac
done

# do everything
if test "$do_32" = "false" -a "$do_64" = "false" ; then
	do_32=true
	do_64=true
fi
#
bdir=$1
targetdir=$2
if [ -z "$bdir" -o -z "$targetdir" ] ; then
echo usage: $0 builddir targetdir
exit 1
fi
CD1=$targetdir/CD1
#
mkdir -pv $CD1/ppc
# to trigger the HFS part, avoid 8.3 filenames and allow OF booting
mkdir -pv $CD1/suseboot
cp -pfv /lib/lilo/pmac/yaboot           $CD1/suseboot/yaboot
cp -pfv /lib/lilo/chrp/yaboot.chrp      $CD1/suseboot/yaboot.ibm
if test "$do_32" = "true" ; then
# provide PS3 bootloader only on openSuSE
#mkdir -pv $CD1/PS3/otheros
#cp -pfv /usr/share/ps3/otheros.bld	$CD1/PS3/otheros
#
cp -pfv $bdir/initrd             $CD1/suseboot/initrd32
cp -pfv /boot/vmlinux-*-default  $CD1/suseboot/linux32
fi
if test "$do_64" = "true" ; then
cp -pfv $bdir/initrd-default       $CD1/suseboot/initrd64
cp -pfv /boot/vmlinux-*-default    $CD1/suseboot/linux64
fi

#deprecate inst{32,64}. We use yaboot anyway, it doens't make sense
#to embed yaboot
#if [ -f /lib/lilo/chrp/mkzimage_cmdline ] ; then
#	mkdir -pv $CD1/ppc/netboot
#	cp -Lpfv /lib/lilo/chrp/mkzimage_cmdline $CD1/ppc/netboot
#	chmod 0755 $CD1/ppc/netboot/mkzimage_cmdline
#fi
#
#if test "$do_64" = "true" ; then
#	/bin/mkzimage \
#	--board chrp \
#	--vmlinux /boot/vmlinux-*-default \
#	--initrd $bdir/initrd-default \
#	--output $CD1/suseboot/inst64
#
#	if test "42" = "false" ; then
#	/bin/mkzimage \
#	--board iseries \
#	--vmlinux /boot/vmlinux-*-default \
#	--initrd $bdir/initrd-default \
#	--output $CD1/ISERIES64
#	fi
#
#fi
#
#if test "$do_32" = "true" ; then
#	/bin/mkzimage \
#	--board chrp \
#	--vmlinux /boot/vmlinux-*-default \
#	--initrd $bdir/initrd \
#	--output $CD1/suseboot/inst32
#
#	if test "42" = "false" ; then
#		/bin/mkzimage \
#		--board prep \
#		--vmlinux /boot/vmlinux-*-default \
#		--initrd $bdir/initrd \
#		--cmdline 'sysrq=1 nosshkey minmemory=0 MemYaSTText=0 quiet ' \
#		--output $CD1/boot/ppc/zImage.prep.initrd
#	fi
#
#	if test "42" = "false" ; then
#		/bin/mkzimage \
#		--board pmaccoff \
#		--vmlinux /boot/vmlinux-*-default \
#		--initrd $bdir/initrd-ppc32_pmac_coff \
#		--output $CD1/boot/ppc/install-pmaccoff
##
#		/bin/mkzimage \
#		--board pmaccoff \
#		--vmlinux /boot/vmlinux-*-default \
#		--output $CD1/boot/ppc/vmlinux-pmaccoff
#
#	fi
#
#fi
#
we_dont_smoke_that_stuff=`echo ${BUILD_DISTRIBUTION_NAME} | sed -e 's@SUSE@SuSE@;s@LINUX@Linux@'`
#
# has to be in one line because the Maple firmware matches just that ...
cat > $CD1/ppc/bootinfo.txt <<EOF
<chrp-boot>
<description>${we_dont_smoke_that_stuff}</description>
<os-name>${we_dont_smoke_that_stuff}</os-name>
<boot-script>boot &device;:1,\\suseboot\\yaboot.ibm</boot-script>
</chrp-boot>

EOF
cat $CD1/ppc/bootinfo.txt
#
cat > $CD1/suseboot/yaboot.txt <<EOF

  Welcome to ${we_dont_smoke_that_stuff}!

  Type  "install"  to start the YaST installer on this CD/DVD
  Type  "slp"      to start the YaST install via network
  Type  "rescue"   to start the rescue system on this CD/DVD


EOF
cat $CD1/suseboot/yaboot.txt
#
if test "$do_32" = "true" ; then
	do_bits="$do_bits 32"
fi
if test "$do_64" = "true" ; then
	do_bits="$do_bits 64"
fi
#
cat > $CD1/suseboot/yaboot.cnf <<EOF
message=yaboot.txt
EOF
for i in $do_bits
do
cat >> $CD1/suseboot/yaboot.cnf <<EOF

image[${i}bit]=linux${i}
  initrd=initrd${i}
  label=install
  append="quiet sysrq=1 insmod=sym53c8xx insmod=ipr            "
image[${i}bit]=linux${i}
  initrd=initrd${i}
  label=slp
  append="quiet sysrq=1 install=slp           "
image[${i}bit]=linux${i}
  initrd=initrd${i}
  label=rescue
  append="quiet sysrq=1 rescue=1              "

EOF
done
cat $CD1/suseboot/yaboot.cnf
#

cat > $CD1/suseboot/os-chooser <<EOF
<CHRP-BOOT>
<COMPATIBLE>
MacRISC MacRISC3 MacRISC4
</COMPATIBLE>
<DESCRIPTION>
SuSE Linux for PowerMac
</DESCRIPTION>
<BOOT-SCRIPT>
load &device;:&partition;,\\suseboot\\yaboot
go
</BOOT-SCRIPT>
<OS-BADGE-ICONS>
1010
000000000000F8FEACF6000000000000
0000000000F5FFFFFEFEF50000000000
00000000002BFAFEFAFCF70000000000
0000000000F65D5857812B0000000000
0000000000F5350B2F88560000000000
0000000000F6335708F8FE0000000000
00000000005600F600F5FD8100000000
00000000F9F8000000F5FAFFF8000000
000000008100F5F50000F6FEFE000000
000000F8F700F500F50000FCFFF70000
00000088F70000F50000F5FCFF2B0000
0000002F582A00F5000008ADE02C0000
00090B0A35A62B0000002D3B350A0000
000A0A0B0B3BF60000505E0B0A0B0A00
002E350B0B2F87FAFCF45F0B2E090000
00000007335FF82BF72B575907000000
000000000000ACFFFF81000000000000
000000000081FFFFFFFF810000000000
0000000000FBFFFFFFFFAC0000000000
000000000081DFDFDFFFFB0000000000
000000000081DD5F83FFFD0000000000
000000000081DDDF5EACFF0000000000
0000000000FDF981F981FFFF00000000
00000000FFACF9F9F981FFFFAC000000
00000000FFF98181F9F981FFFF000000
000000ACACF981F981F9F9FFFFAC0000
000000FFACF9F981F9F981FFFFFB0000
00000083DFFBF981F9F95EFFFFFC0000
005F5F5FDDFFFBF9F9F983DDDD5F0000
005F5F5F5FDD81F9F9E7DF5F5F5F5F00
0083DD5F5F83FFFFFFFFDF5F835F0000
000000FBDDDFACFBACFBDFDFFB000000
000000000000FFFFFFFF000000000000
0000000000FFFFFFFFFFFF0000000000
0000000000FFFFFFFFFFFF0000000000
0000000000FFFFFFFFFFFF0000000000
0000000000FFFFFFFFFFFF0000000000
0000000000FFFFFFFFFFFF0000000000
0000000000FFFFFFFFFFFFFF00000000
00000000FFFFFFFFFFFFFFFFFF000000
00000000FFFFFFFFFFFFFFFFFF000000
000000FFFFFFFFFFFFFFFFFFFFFF0000
000000FFFFFFFFFFFFFFFFFFFFFF0000
000000FFFFFFFFFFFFFFFFFFFFFF0000
00FFFFFFFFFFFFFFFFFFFFFFFFFF0000
00FFFFFFFFFFFFFFFFFFFFFFFFFFFF00
00FFFFFFFFFFFFFFFFFFFFFFFFFF0000
000000FFFFFFFFFFFFFFFFFFFF000000
</OS-BADGE-ICONS>
</CHRP-BOOT>
EOF
cat $CD1/suseboot/os-chooser
#

find $CD1 -ls
du -sm $CD1

