# Environment variables to configure boot/root/rescue images

## General options

- cache=1|2|4

  cache the rpms we use, it is actually a bitmask; the most useful value is 4, which
  will cache the unpacked rpm in a separate directory

- debug=ignore

  ignore noncritical errors

- debug=account

  create disk usage statistics, stored in ```tmp/&lt;image_name&gt;.size```

- dist=8.1, dist=8.1-i386+kde

  build for this release

- suserelease=8.0

  obsolete, equivalent to dist=

- kernel=&lt;kernel rpm&gt;

  give kernel package name explicitly

- theme=&lt;theme&gt;

  select this theme (default: theme=SuSE)

- themes=&lt;list of themes&gt;

  list of supported themes, support all if empty

## root

- uncompressed_root=1

  build uncompressed image

- keeproot=1

  don't rebuild everything, just recreate (copy the cached tree and compress) the
  last image (useful to speed up testing)

- filelist=foo

  build using foo.file_list

- nolibs=1

  no ldconfig check

- imagetype=foo / imagetype=foo.gz / imagetype=none

  use foo as filesystem for image (.gz: and compress with gzip);
  none: don't create an image

- imagename=foo

  use tmp/foo & image/foo as temp dir & final image

- tmpdir=foo

  use foo instead of tmp/root

## rescue

- keeprescue=1

  don't rebuild everything, just recreate (copy the cached tree and compress) the
  last image (useful to speed up testing)

- filelist=foo

  build using foo.file_list

- imagetype=foo / imagetype=foo.gz / imagetype=none

  use foo as filesystem for image (.gz: and compress with gzip)
  none: don't create an image

- imagename=foo

  use tmp/foo & image/foo as temp dir & final image

- tmpdir=foo

  use foo instead of tmp/rescue

## base

- full_splash=0

  don't add silent splash image


## initrd

- initrd_fs=&lt;fstype&gt;

  use fstype for initrd (default: ext2)

- initramfs=1

  build initramfs

- linuxrc=&lt;absolute_filename&gt;

  use the specified linuxrc (taken from the running system!).
  Caveats may apply: please also refer to the
  [linuxrc](https://github.com/openSUSE/linuxrc) docs
  and the [troubleshooting section](#troubleshooting-and-hacks).

- mkdevs=1

  compress device tree

- initrd=small|large

  build a small (for 1.44MB boot images) or large (no size limit) version

- keepinitrd=1

  don't rebuild everything, just recreate (copy the cached tree and compress) the
  last image (useful to speed up testing)

- nousb=1

  don't add usb modules to initrd

- nopcmcia=1

  don't add the /etc/pcmcia tree to initrd

- fewkeymaps=1

  just english, french and german maps

- bootsplash=0|modules1

  don't add bootsplash or add splash to modules disk 1
  (default is to add it to boot image)

- initrd_name=&lt;name&gt;

  [default: initrd] name of the final initrd image

- with_smb=1

  add smb support

- with_gdb=1|2

  create an initrd with gdb; if with_gdb=2 start linuxrc from gdb

- liveeval=1

  create an initrd for LiveEval

- lang=cs_CZ

  [only with liveeval=1] special czech version

- extramod=&lt;module&gt;

  add &lt;module&gt; to initrd; only _one_ module allowed (useful for testing only)


## boot

- boot=small|hd|large|isolinux

  the boot image type we should create; small is a 1.44MB image, hd for
  boot CD with hd emulation, isolinux for a CD with 'no emulation'; large is
  mainly for ia64 (the image is basically just a dos partition)

- bootlogo=1|0

  whether to add the graphical boot logo; if unset, the logo will not be added
  for 'boot=small'

- memtest=yes|no

  whether to add memtest; if unset, memtest will not be added for 'boot=small'

- initrd_name=&lt;name&gt;

  [default: initrd] name of the initrd image we should add; this will be the name
  on the boot image and the name referenced in syslinux.cfg, too

- noinitrd=&lt;name&gt;

  [only with 'boot=small'] do _not_ add the initrd &lt;name&gt; to the boot image, unless
  it fits on it; the initrd name on the boot image is 'small'; the name in
  syslinux.cfg is _not_ adjusted to &lt;name&gt;

- use_k_inst=1

  use kernel image from k_inst for booting

- fastboot=1

  don't use syslinux' '-s' option for floppies

- liveeval=1

  liveeval bootloader config

- is_dvd=1

  create dvd boot config (32/64 bit dual boot)

- with_floppy=1

  create boot disks, too (i386, x86_86 only)


## modules

- modules=&lt;number&gt;

  build module disk &lt;number&gt;; Note: module disk #1 has the initrd on it, so you _must_
  build the initrd explicitly before!


## liveeval

- lang=cs_CZ

  special czech version

