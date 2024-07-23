# Adjusting compression

The environment variable `instsys_no_compression` accepts a comma-separated
list of values to omit compression in certain places.

It is usually not a good idea to change the default settings but it might
help in some specific cases - notably on ppc64 (see bsc#1223982 and jsc#PED-8374).

Accepted values are:

- squashfs: Do not compress squashfs images in initrd.
- modules: Do not compress kernel modules. Uncompress them if they are found compressed in kernel packages.
- firmware: Do not compress kernel firmware. Uncompress them if they are found compressed in kernel packages.
