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
k_deflt=`rpm -qf --qf %{VERSION} /boot/vmlinux-*-default`
k_pmac64=`rpm -qf --qf %{VERSION} /boot/vmlinux-*-pmac64`
#
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
cp -pfv /boot/vmlinux-*-pmac64_32bit $CD1/vmlinux64
cp -pfv $bdir/initrd-kernel-pmac64_32bit $CD1/initrd64
cp -pfv $bdir/initrd-kernel-iseries64 $CD1/boot
cp -pfv $bdir/initrd-kernel-pseries64 $CD1/boot

#
bash /lib/lilo/chrp/chrp64/addRamdisk.sh \
	/var/tmp/chrpinitrd.$$ \
	/boot/vmlinux-*-pseries64 \
	$bdir/initrd-kernel-pseries64 \
	$CD1/install
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
	--output $CD1/boot/install-pmaccoff-$k_deflt
#
/lib/lilo/pmac/oldworld_coff/make_zimage_pmac_oldworld_coff.sh \
	--vmlinux /boot/vmlinux-*-default \
	--output $CD1/boot/vmlinux-pmaccoff-$k_deflt
#
/lib/lilo/pmac/newworld/make_zimage_pmac_newworld.sh \
	--vmlinux /boot/vmlinux-*-default \
	--initrd $bdir/initrd-kernel-default-ppc \
	--output $CD1/boot/install-pmac-$k_deflt
#
/lib/lilo/pmac/newworld/make_zimage_pmac_newworld.sh \
	--vmlinux /boot/vmlinux-*-default \
	--output $CD1/boot/vmlinux-pmac-$k_deflt
#
/lib/lilo/pmac/newworld/make_zimage_pmac_newworld.sh \
	--vmlinux /boot/vmlinux-*-pmac64 \
	--initrd $bdir/initrd-kernel-pmac64 \
	--output $CD1/boot/install-pmac64-$k_pmac64
#
/lib/lilo/pmac/newworld/make_zimage_pmac_newworld.sh \
	--vmlinux /boot/vmlinux-*-pmac64 \
	--output $CD1/boot/vmlinux-pmac64-$k_pmac64
#
ln -sv boot/install-pmac-$k_deflt       $CD1/installpmac
ln -sv boot/install-pmac64-$k_pmac64	$CD1/installpmac64
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

  Welcome to SuSE Linux (SLES9 preview)!

  Use  "install"     to boot the pSeries 64bit kernel
  Use  "install32"   to boot the 32bit RS/6000 kernel

  You can pass the option "noinitrd"  to skip the installer.
  Example: install noinitrd root=/dev/sda4

EOF
cat $CD1/yaboot.txt
#
cat > $CD1/etc/yaboot.conf <<EOF
message=yaboot.txt
image=install
  label=install
#  append="ide0=noautotune"
image=cdrom:1,\\vmlinux32
  label=install32
  initrd=cdrom:1,\\initrd32

EOF
cat $CD1/etc/yaboot.conf
#
cat > $CD1/suseboot/yaboot.conf <<EOF
image=vmlinux32
  label=install32
  initrd=initrd32
#  append="ide0=noautotune"
image=vmlinux64
  label=install64
  initrd=initrd64

EOF
cat $CD1/suseboot/yaboot.conf
#

find $CD1 $CD2 -ls
du -sm $CD1 $CD2
