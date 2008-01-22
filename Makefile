
# perl libraries & binaries
PLIBS	= AddFiles MakeFATImage MakeMinixImage ReadConfig
PBINS	= initrd_test mk_boot mk_initrd mk_initrd_test mk_root  

.PHONY: all dirs initrd initrd_test boot boot_axp rescue \
        root liveeval html clean distdir install install_xx \
	mboot base bootcd2 bootdisk bootcd rootfonts hal \
	biostest gkv trans root+rescue

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

biostest:
	debug=$${debug},ignorelibs filelist=biostest initrd_name=biostest make initrd

initrd: dirs base
	initramfs=$${initramfs:-1} YAST_IS_RUNNING=1 bin/mk_initrd

zeninitrd: dirs base
	initramfs=$${initramfs:-1} YAST_IS_RUNNING=1 theme=Zen filelist=zeninitrd bin/mk_initrd

zenboot: zeninitrd mboot
	theme=Zen initrd=large boot=isolinux memtest=no bin/mk_boot

zenroot: dirs base
	YAST_IS_RUNNING=1 theme=Zen imagetype=$${imagetype:-ext2} filelist=zenroot bin/mk_root

plain_initrd: dirs
	YAST_IS_RUNNING=1 bin/mk_initrd

initrd_test: initrd
	bin/mk_initrd_test
	@echo "now, run bin/initrd_test"

boot: initrd mboot
	bin/mk_boot

bootcd2: eltorito
#	initrd=medium boot=medium make boot
	cp src/eltorito/boot images/boot.cd2

# i386 & x86_64 only
bootdisk: biostest
# with_smb=1
	initrd=large boot=small make boot

# i386 & x86_64 only
bootcd: biostest
# with_smb=1
	initramfs=$${initramfs:-1} initrd=large boot=isolinux make boot

boot_axp: initrd
	bin/mk_boot_axp

install_xx: initrd
	bin/mk_install_xx

root: dirs base
	# just for now
	root_i18n=1 root_gfx=1 roottrans=$${roottrans:-1} \
	YAST_IS_RUNNING=1 bin/mk_root

rootfonts: dirs base
	nolibs=1 filelist=fonts imagename=root.fonts bin/mk_root

trans: dirs base
	for lang in `cat tmp/base/yast2-trans.list` ; do \
	  lang=$$lang imagename=root.$$lang nolibs=1 filelist=trans bin/mk_root ; \
	  rm -f images/root.$$lang.log ; \
	done

rescue: dirs base
	YAST_IS_RUNNING=1 bin/mk_rescue

root+rescue: dirs base
	rm -rf tmp/tmp
	bin/common_tree --dst tmp/tmp tmp/rescue tmp/root
	keeproot=1 tmpdir=tmp/tmp/c imagename=common bin/mk_root
	keeproot=1 tmpdir=tmp/tmp/1 imagename=rescue bin/mk_root
	keeproot=1 tmpdir=tmp/tmp/2 imagename=root bin/mk_root
	cp data/root/config images/config

hal: dirs base
	YAST_IS_RUNNING=1 filelist=hal bin/mk_rescue

mboot:
	make -C src/mboot

eltorito:
	make -C src/eltorito

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
	-@rm -rf /tmp/mk_base_* /tmp/mk_initrd_* /tmp/mk_rescue_* /tmp/mk_root_* 
	-@rm -rf data/initrd/gen data/boot/gen data/base/gen data/demo/gen
