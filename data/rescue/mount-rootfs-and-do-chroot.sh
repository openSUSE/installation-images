#!/bin/bash
# Usage: $0 /dev/sda5
rootfs=$1
mnt=/rootfs.${PPID}.$$
mounts=

if test -b "${rootfs}"
then
        mkdir -pv "${mnt}"
        if mount -v "${rootfs}" "${mnt}"
	then
		for i in dev dev/pts proc sys
		do
			if test -d /${i} && test -d "${mnt}/${i}" && test "`stat -c %D /`" != "`stat -c %D /${i}`"
			then
				mount -v --bind /${i} "${mnt}/${i}"
			fi
		done

		echo "Performing chroot into ${rootfs}. Use 'exit' or 'CTRL+d' to leave chroot shell."
		chroot "${mnt}" su -

		while read b m rest
		do
			case "${m}" in
				${mnt}*)
					mounts="${m} ${mounts}"
				;;
			esac
		done <<-EOF
`
cat < /proc/mounts
`
EOF

		for i in ${mounts}
		do
			umount -v "${i}"
		done
		rmdir -v "${mnt}"
	fi
fi
