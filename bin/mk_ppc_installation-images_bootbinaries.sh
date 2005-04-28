#!/bin/bash
set -ex
echo foo
bdir=$1
targetdir=$2
if [ -z "$bdir" -o -z "$targetdir" -o ! -f /.buildenv ] ; then
echo usage: $0 builddir targetdir
exit 1
fi
. /.buildenv
CD1=$targetdir/CD1
CD2=$targetdir/CD2
#
mkdir -pv $CD1/ppc/netboot
mkdir -pv $CD1/ppc/chrp
mkdir -pv $CD1/etc
mkdir -pv $CD1/boot
mkdir -pv $CD1/suseboot
# to trigger the HFS part, avoid 8.3 filenames and allow OF booting
mkdir -pv $CD2/suseboot
mkdir -pv $CD2/boot
#
cp -pfv $bdir/initrd-* $CD2/boot/
cp -pfv /lib/lilo/chrp/yaboot.chrp $CD1/
cp -pfv /lib/lilo/pmac/yaboot $CD1/suseboot/
cp -pfv /boot/vmlinux-*-default $CD1/vmlinux32
cp -pfv $bdir/initrd-kernel-default-ppc $CD1/initrd32
cp -pfv /boot/vmlinux-*-ppc64 $CD1/vmlinux64
cp -pfv $bdir/initrd-kernel-ppc64 $CD1/initrd64
cp -pfv $bdir/initrd-kernel-iseries64 $CD1/boot

if [ -f /lib/lilo/chrp/mkzimage_cmdline ] ; then
	cp -pfv /lib/lilo/chrp/mkzimage_cmdline $CD1/ppc/netboot
	chmod 0755 $CD1/ppc/netboot/mkzimage_cmdline
fi
#
bash /lib/lilo/chrp/chrp64/addRamdisk.sh \
	/var/tmp/chrpinitrd.$$ \
	/boot/vmlinux-*-ppc64 \
	$bdir/initrd-kernel-ppc64 \
	$CD1/install
/lib/lilo/chrp/mkzimage_cmdline -a 1 -c $CD1/install
#
/lib/lilo/iseries/iseries-addRamDisk \
	$bdir/initrd-kernel-iseries64 \
	/boot/System.map-*-iseries64 \
	/boot/vmlinux-*-iseries64 \
	$CD1/ISERIES64
#
/lib/lilo/prep/make_zimage_prep.sh \
	--vmlinux /boot/vmlinux-*-default \
	--initrd $bdir/initrd-kernel-default-ppc \
	--output $CD1/boot/zImage.prep.initrd
#
/lib/lilo/pmac/oldworld_coff/make_zimage_pmac_oldworld_coff.sh \
	--vmlinux /boot/vmlinux-*-default \
	--initrd $bdir/initrd-kernel-default-ppc32_pmac_coff \
	--output $CD1/boot/install-pmaccoff
#
/lib/lilo/pmac/oldworld_coff/make_zimage_pmac_oldworld_coff.sh \
	--vmlinux /boot/vmlinux-*-default \
	--output $CD1/boot/vmlinux-pmaccoff
#
/lib/lilo/pmac/newworld/make_zimage_pmac_newworld.sh \
	--vmlinux /boot/vmlinux-*-default \
	--initrd $bdir/initrd-kernel-default-ppc \
	--output $CD1/installpmac
#
/lib/lilo/pmac/newworld/make_zimage_pmac_newworld.sh \
	--vmlinux /boot/vmlinux-*-ppc64 \
	--initrd $bdir/initrd-kernel-ppc64 \
	--output $CD1/installpmac64
#
cat > $CD1/ppc/bootinfo.txt <<EOF
<chrp-boot>
<description>$BUILD_DISTRIBUTION_NAME</description>
<os-name>$BUILD_DISTRIBUTION_NAME</os-name>
<boot-script>boot &device;:1,yaboot.chrp </boot-script>
</chrp-boot>

EOF
cat $CD1/ppc/bootinfo.txt
#
cat > $CD1/yaboot.txt <<EOF

  Welcome to SuSE Linux (SLES10)!

  Use  "install"     to boot the pSeries 64bit kernel
  Use  "install32"   to boot the 32bit RS/6000 kernel


EOF
cat $CD1/yaboot.txt
#
cat > $CD1/etc/yaboot.conf <<EOF
message=yaboot.txt
image=install
  label=install
  append="quiet                       "
image=cdrom:1,\\vmlinux32
  label=install32
  initrd=cdrom:1,\\initrd32

EOF
cat $CD1/etc/yaboot.conf
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
: printf fb8-write drop ;                                                                                               
: we-are-64-bit " 64bit "(0d 0a)" printf " cd:,installpmac64 quiet" \$boot ;
: we-are-32-bit " 32bit "(0d 0a)" printf " cd:,installpmac quiet" \$boot ;

" screen" output
dev screen
" "(0000000000aa00aa0000aaaaaa0000aa00aaaa5500aaaaaa)" drop 0 7 set-colors
" "(5555555555ff55ff5555ffffff5555ff55ffffff55ffffff)" drop 8 15 set-colors
device-end
f to foreground-color
0 to background-color

" "(0d 0a)" printf
" booting kernel ... " printf
" /cpus/@0" find-package IF " 64-bit" rot get-package-property 0= IF we-are-64-bit ELSE we-are-32-bit THEN THEN
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

find $CD1 $CD2 -ls
du -sm $CD1 $CD2
