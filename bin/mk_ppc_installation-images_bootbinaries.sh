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
k_pmac64_32bit=`rpm -qf --qf %{VERSION} /boot/vmlinux-*-pmac64_32bit`
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
cp -pfv /boot/vmlinux-*-default $CD1/suseboot/vmlinux32
cp -pfv $bdir/initrd-kernel-default-ppc_pmac_new $CD1/suseboot/initrd32
cp -pfv /boot/vmlinux-*-pmac64_32bit $CD1/suseboot/vmlinux_pmac64
cp -pfv $bdir/initrd-kernel-pmac64_32bit $CD1/suseboot/initrd_pmac64

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
	--initrd $bdir/initrd-kernel-default-ppc_prep \
	--output $CD1/boot/zImage.prep.initrd
#
/lib/lilo/pmac/oldworld_coff/make_zimage_pmac_oldworld_coff.sh \
	--vmlinux /boot/vmlinux-*-default \
	--initrd $bdir/initrd-kernel-default-ppc_pmac_coff \
	--output $CD2/boot/install-pmaccoff-$k_deflt
#
/lib/lilo/pmac/oldworld_coff/make_zimage_pmac_oldworld_coff.sh \
	--vmlinux /boot/vmlinux-*-default \
	--output $CD2/boot/vmlinux-pmaccoff-$k_deflt
#
/lib/lilo/pmac/newworld/make_zimage_pmac_newworld.sh \
	--vmlinux /boot/vmlinux-*-default \
	--initrd $bdir/initrd-kernel-default-ppc_pmac_new \
	--output $CD2/boot/install-pmacnew-$k_deflt
#
/lib/lilo/pmac/newworld/make_zimage_pmac_newworld.sh \
	--vmlinux /boot/vmlinux-*-default \
	--output $CD2/boot/vmlinux-pmacnew-$k_deflt
#
/lib/lilo/pmac/newworld/make_zimage_pmac_newworld.sh \
	--vmlinux /boot/vmlinux-*-pmac64_32bit \
	--initrd $bdir/initrd-kernel-pmac64_32bit \
	--output $CD2/boot/install-pmac64-$k_pmac64_32bit
#
/lib/lilo/pmac/newworld/make_zimage_pmac_newworld.sh \
	--vmlinux /boot/vmlinux-*-pmac64_32bit \
	--output $CD2/boot/vmlinux-pmac64-$k_pmac64_32bit
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
image=cdrom:1,\\suseboot\\vmlinux32
  label=install32"
  initrd=cdrom:1,\\suseboot\\initrd32

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
