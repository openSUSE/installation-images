#!/bin/bash

echo running ppc postinstall start ... $0 $*
date 
while read line; do
        case "$line" in
		*MacRISC*)    MACHINE="mac";;
		*CHRP*)       MACHINE="chrp";;
		*PReP*)       MACHINE="prep" ;;
		*iSeries*)    MACHINE="iseries";;
	esac
done < /proc/cpuinfo
_kernel_version=`/sbin/get_kernel_version /mnt/boot/vmlinux`
_root_partition=`mount | grep " /mnt " | cut -d\  -f 1`

echo MACHINE $MACHINE 
echo _kernel_version $_kernel_version 
echo _root_partition $_root_partition

if test $MACHINE = iseries ; then
rm -fv /mnt/var/adm/setup/setup.modem
rm -fv /mnt/var/adm/setup/setup.mouse
rm -fv /mnt/var/adm/setup/setup.selection

echo "changing inittab"
sed '/^.*mingetty.*$/d' /mnt/etc/inittab > /mnt/etc/inittab.tmp
diff /mnt/etc/inittab /mnt/etc/inittab.tmp &>/dev/null || mv -v /mnt/etc/inittab.tmp /mnt/etc/inittab


#echo "1:12345:respawn:/bin/login console" >> /mnt/etc/inittab
cat >> /mnt/etc/inittab <<-EOF


# iSeries virtual console:
1:2345:respawn:/sbin/mingetty --noclear tty1

# to allow only root to log in on the console, use this:
# 1:2345:respawn:/sbin/sulogin /dev/console

# to disable authentication on the console, use this:
# y:2345:respawn:/bin/bash

EOF

# syslog.conf
if grep -q tty10 /mnt/etc/syslog.conf; then
        echo "changing syslog.conf"
        sed '/.*tty10.*/d; /.*xconsole.*/d' /mnt/etc/syslog.conf > /mnt/etc/syslog.conf.tmp
        diff /mnt/etc/syslog.conf /mnt/etc/syslog.conf.tmp &>/dev/null || mv -v /mnt/etc/syslog.conf.tmp /mnt/etc/syslog.conf
fi


ln -sf iseries/vcda /mnt/dev/cdrom

( echo "SuSE Linux on iSeries -- the spicy solution!"
  echo "Have a lot of fun..." 
) > /mnt/etc/motd

if lsmod | grep -q ibmsis ; then
        #
        # we are using SCSI, so we want an initrd with the driver
	# (even if the root partition is not on SCSI it won't harm)
        #
        echo creating initrd with SCSI driver...
        /mnt/sbin/mk_initrd -b /boot/ -k vmlinux -i initrd -m "ibmsis" /mnt

        /mnt/bin/addSystemMap /mnt/boot/System.map-$_kernel_version /mnt/boot/vmlinux /mnt/boot/vmlinux.sm
        /mnt/bin/addRamDisk /mnt/boot/initrd /mnt/boot/vmlinux.sm /mnt/boot/vmlinux.initrd

        echo "1 root=$_root_partition" >  /proc/iSeries/mf/A/cmdline          # slot A
        dd if=/mnt/boot/vmlinux.initrd of=/proc/iSeries/mf/A/vmlinux bs=4096

        echo "root=$_root_partition" >    /proc/iSeries/mf/B/cmdline          # slot B
        dd if=/mnt/boot/vmlinux.initrd of=/proc/iSeries/mf/B/vmlinux bs=4096
else
        #
        # no SCSI driver -- no initrd
        #
        /mnt/bin/addSystemMap /mnt/boot/System.map-$_kernel_version /mnt/boot/vmlinux /mnt/boot/vmlinux.sm

        echo "1 root=$_root_partition" >  /proc/iSeries/mf/A/cmdline          # slot A
        dd if=/mnt/boot/vmlinux.sm              of=/proc/iSeries/mf/A/vmlinux bs=4096

        echo "root=$_root_partition" >  /proc/iSeries/mf/B/cmdline            # slot B
        dd if=/mnt/boot/vmlinux.sm              of=/proc/iSeries/mf/B/vmlinux bs=4096

fi

# set IPL source
echo B > /proc/iSeries/mf/side

touch /mnt/etc/mtab


fi  # iseries

# activate all PReP partitions, if YaST has not already done it (it doesn't, sometimes)
for i in `fdisk -l | grep PReP | cut -d\  -f1`; do
	echo activate $i PReP partition
	j=`echo $i | sed 's/\([0-9]\)/ \1/'`; /sbin/activate $j
done


echo running ppc postinstall done ... $0 $*
date

