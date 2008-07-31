ARCH    := $(shell uname -m)
ifeq "$(ARCH)" "i486"
ARCH    := i386
endif
ifeq "$(ARCH)" "i586"
ARCH    := i386
endif
ifeq "$(ARCH)" "i686"
ARCH    := i386
endif


THEMES        := openSUSE SLES
INSTSYS_PARTS := images/config images/rpmlist images/root images/common images/rescue images/sax2 images/gdb
BOOT_PARTS    := images/boot/* images/initrd images/biostest
DESTDIR       := images/instsys

WITH_FLOPPY   := 0

export ARCH THEMES DESTDIR INSTSYS_PARTS BOOT_PARTS WITH_FLOPPY

.PHONY: all dirs base zeninitrd zenboot zenroot biostest initrd \
	oldboot boot root rescue root+rescue sax2 gdb mboot clean \
	boot-themes root-themes install

all: initrd biostest initrd+modules boot boot-themes rescue root root+rescue gdb sax2 root-themes
	@rm images/*.log

install:

dirs:
	@[ -d images ] || mkdir images
	@[ -d tmp ] || mkdir tmp

base: dirs
	@[ -d tmp/base ] || nolibs=1 nostrip=1 image=base fs=none bin/mk_image

zeninitrd: base
	initramfs=$${initramfs:-1} YAST_IS_RUNNING=1 theme=Zen filelist=zeninitrd bin/mk_initrd

zenboot: zeninitrd mboot
	theme=Zen initrd=large boot=isolinux memtest=no bin/mk_boot

zenroot: base
	theme=Zen fs=$${fs:-ext2} image=zenroot src=root fs=squashfs bin/mk_image

biostest: base
	nolibs=1 image=biostest src=initrd fs=cpio.gz disjunct=initrd bin/mk_image

initrd: base
	image=initrd fs=cpio.gz bin/mk_image

modules: base
	nolibs=1 image=modules-config src=initrd fs=none bin/mk_image
	bin/mlist1
	bin/mlist2
	nolibs=1 image=modules src=initrd fs=none bin/mk_image
	ls -I module.config tmp/modules/modules | sed -e 's#.*/##' >images/module.list

initrd+modules: base
	nolibs=1 image=modules-config src=initrd fs=none bin/mk_image
	bin/mlist1
	bin/mlist2
	rm -rf tmp/initrd/modules tmp/initrd/lib/modules
	nolibs=1 mode=keep,add image=initrd filelist=modules src=initrd fs=cpio.gz bin/mk_image
	ls -I module.config tmp/initrd/modules | sed -e 's#.*/##' >images/module.list

oldboot: initrd mboot
	bin/mk_boot

boot: base
	nolibs=1 image=boot fs=dir bin/mk_image

root: base
	root_i18n=1 root_gfx=1 perldeps=root image=root bin/mk_image

rescue: base
	image=rescue bin/mk_image

root+rescue: base
	rm -rf tmp/tmp
	bin/common_tree --dst tmp/tmp tmp/rescue tmp/root
	mode=keep tmpdir=tmp/tmp/c image=common fs=squashfs bin/mk_image
	mode=keep tmpdir=tmp/tmp/1 image=rescue fs=squashfs bin/mk_image
	mode=keep tmpdir=tmp/tmp/2 image=root fs=squashfs bin/mk_image
	cp data/root/config images
	cat data/root/rpmlist tmp/base/yast2-trans-rpm.list >images/rpmlist

sax2: base
	nolibs=1 perldeps=root,sax2 image=sax2 src=root fs=squashfs disjunct=root bin/mk_image

gdb: base
	nolibs=1 image=gdb src=root fs=squashfs disjunct=root bin/mk_image

boot-themes: base
	for theme in $(THEMES) ; do \
	  nolibs=1 image=boot-$$theme src=boot filelist=$$theme fs=dir bin/mk_image ; \
	done

root-themes: base
	for theme in $(THEMES) ; do \
	  nolibs=1 image=root-$$theme src=root filelist=$$theme fs=squashfs disjunct=root bin/mk_image ; \
	done

mboot:
	make -C src/mboot

clean:
	-@make -C src/mboot clean
	-@make -C src/eltorito clean
	-@rm -rf images tmp
	-@rm -f `find -name '*~'`
	-@rm -rf /tmp/mk_base_* /tmp/mk_initrd_* /tmp/mk_image_* 
	-@rm -rf data/initrd/gen data/boot/gen data/base/gen data/demo/gen

install: $(INSTSYS_PARTS) $(BOOT_PARTS)
	-@rm -rf $(DESTDIR)
	@mkdir -p $(DESTDIR)
	@cp README.package $(DESTDIR)/README
	./install.$(ARCH)

