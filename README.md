# (open)SUSE installation images

## Overview

installation-images builds the SUSE installation system. This includes the installer itself and
everything it needs to run an installation (except for the actual package repository). This also
includes the boot loader configuration used on our installation media.

To give you an impression what we are talking about here, here's a (a bit shortened) listing 
of the relevant files on an x86_64 installation dvd:

```sh
drwxr-xr-x         19 Jun 20  2016 boot
drwxr-xr-x        137 Apr 26 12:16 boot/x86_64
-rw-r--r--    2097152 Jun 20  2016 boot/x86_64/libstoragemgmt
-rw-r--r--    3870720 Nov  9 16:21 boot/x86_64/efi
drwxr-xr-x         83 Apr 26 12:28 boot/x86_64/loader
-rw-r--r--   94205880 Aug  9  2016 boot/x86_64/loader/initrd
-rw-r--r--    6293536 Jun 20  2016 boot/x86_64/loader/linux
-rw-r--r--      24576 Apr 26 12:26 boot/x86_64/loader/isolinux.bin
-rw-r--r--        826 Apr 26 12:26 boot/x86_64/loader/isolinux.cfg
-rw-r--r--       2079 Jun 20  2016 boot/x86_64/config
-rw-r--r--   62455808 Jun 20  2016 boot/x86_64/root
-rw-r--r--   76480512 Jun 20  2016 boot/x86_64/common
-rw-r--r--   19726336 Jun 20  2016 boot/x86_64/rescue
-rw-r--r--    1572864 Jun 20  2016 boot/x86_64/bind
-rw-r--r--   22740992 Jun 20  2016 boot/x86_64/gdb
drwxr-xr-x         19 Apr 26 12:27 boot/x86_64/grub2-efi
drwxr-xr-x         21 Apr 26 12:27 boot/x86_64/grub2-efi/themes
drwxr-xr-x          6 Apr 26 12:27 boot/x86_64/grub2-efi/themes/openSUSE
drwxr-xr-x         17 Jun 20  2016 EFI
drwxr-xr-x         88 Nov  9 16:21 EFI/BOOT
-rwxr-xr-x    1155520 Jun 20  2016 EFI/BOOT/bootx64.efi
-rw-r--r--       2638 Nov  9 16:21 EFI/BOOT/grub.cfg
-rw-r--r--     975712 Jun 20  2016 EFI/BOOT/grub.efi
```

You can see the kernel (`linux`), the `initrd`, boot loader files belonging to `isolinux` and `grub2`, and
files like `root`, `rescue`, `common` that are
[squashfs](http://www.tldp.org/HOWTO/SquashFS-HOWTO)
images containing the installation system with
the [YaST](https://en.opensuse.org/Portal:YaST) installer.

If you are going to work on this project, have a look at the documentaion first:

- [General intro](doc/index.md)
- [Submitting changes to SUSE Build Service](doc/submitting.md)
- [Modifying the branding](doc/branding.md)
- [Config options for generating the images](doc/configoptions.md)
- [Adding packages and files to the installation system](doc/files.md)
- [Kernel modules](doc/modules.md)

You can also read this at [ReadTheDocs](http://installation-images.readthedocs.io/).
