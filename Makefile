
# perl libraries & binaries
PLIBS	= AddFiles MakeFATImage MakeMinixImage ReadConfig
PBINS	= initrd_test mk_boot mk_initrd mk_initrd_test  

.PHONY: all dirs initrd initrd_test boot boot_axp rescue \
        root liveeval html clean distdir install install_xx \
	mboot base bootcd2 bootdisk bootcd rootfonts hal \
	biostest gkv trans root+rescue sax2

all: bootdvd bootcd2 rescue root
	@rm -rf images/cd[12]
	@mkdir -p images/cd1/boot/loader images/cd2/boot
	@cp images/boot.small images/cd1/boot/bootdisk
	@cp -r images/boot.isolinux/* images/cd1/boot/loader
	@cp images/root.cramfs images/cd1/boot/root
	@cp images/rescue images/cd1/boot
	@cp images/boot.medium images/cd2/boot/image

install:

distdir: clean
	@mkdir -p $(distdir)
	@tar -cf - . | tar -C $(distdir) -xpf -
	@find $(distdir) -depth -name CVS -exec rm -r {} \;

dirs:
	@[ -d images ] || mkdir images
	@[ -d test ] || mkdir test
	@[ -d tmp ] || mkdir tmp

zeninitrd: dirs base
	initramfs=$${initramfs:-1} YAST_IS_RUNNING=1 theme=Zen filelist=zeninitrd bin/mk_initrd

zenboot: zeninitrd mboot
	theme=Zen initrd=large boot=isolinux memtest=no bin/mk_boot

zenroot: dirs base
	theme=Zen fs=$${fs:-ext2} image=zenroot src=root fs=squashfs bin/mk_image

biostest:
	debug=$${debug},ignorelibs filelist=biostest initrd_name=biostest make initrd

initrd: dirs base
	initramfs=$${initramfs:-1} YAST_IS_RUNNING=1 bin/mk_initrd

boot: initrd mboot
	bin/mk_boot

bootcd: biostest
# with_smb=1 ???
	initramfs=$${initramfs:-1} initrd=large boot=isolinux make boot

root: dirs base
	root_i18n=1 root_gfx=1 image=root bin/mk_image

rescue: dirs base
	image=rescue bin/mk_image

root+rescue: dirs base
	rm -rf tmp/tmp
	bin/common_tree --dst tmp/tmp tmp/rescue tmp/root
	keep=1 tmpdir=tmp/tmp/c image=common fs=squashfs bin/mk_image
	keep=1 tmpdir=tmp/tmp/1 image=rescue fs=squashfs bin/mk_image
	keep=1 tmpdir=tmp/tmp/2 image=root fs=squashfs bin/mk_image
	cp data/root/config images
	cat data/root/rpmlist tmp/base/yast2-trans-rpm.list >images/rpmlist

sax2: dirs base
	nolibs=1 image=sax2 src=root fs=squashfs disjunct=root bin/mk_image

mboot:
	make -C src/mboot

gkv:
	make -C src/gkv

base: dirs gkv
	@[ -d tmp/base ] || YAST_IS_RUNNING=1 bin/mk_base

html:
	@for i in $(PLIBS); do echo $$i; pod2html --noindex --title=$$i --outfile=doc/$$i.html lib/$$i.pm; done
	@for i in $(PBINS); do echo $$i; pod2html --noindex --title=$$i --outfile=doc/$$i.html bin/$$i; done
	@rm pod2html-dircache pod2html-itemcache

clean:
	-@make -C src/mboot clean
	-@make -C src/eltorito clean
	-@make -C src/gkv clean
	-@umount test/initdisk/proc 2>/dev/null ; true
	-@umount test/initdisk/mnt 2>/dev/null ; true
	-@rm -rf images test tmp
	-@rm -f `find -name '*~'`
	-@rm -rf /tmp/mk_base_* /tmp/mk_initrd_* /tmp/mk_image_* 
	-@rm -rf data/initrd/gen data/boot/gen data/base/gen data/demo/gen
