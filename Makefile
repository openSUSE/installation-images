ARCH := $(shell uname -m)
ifneq ($(filter i386 i486 i586 i686, $(ARCH)),)
ARCH := i386
endif

COMMON_TARGETS	     := rescue root root+rescue root-themes bind gdb mini-iso-rmlist
COMMON_INSTSYS_PARTS := config rpmlist root common rescue bind gdb

ifneq ($(filter i386, $(ARCH)),)
ALL_TARGETS   := initrd-themes initrd biostest initrd+modules boot boot-themes $(COMMON_TARGETS) sax2
INSTSYS_PARTS := $(COMMON_INSTSYS_PARTS) sax2
BOOT_PARTS    := boot/* initrd biostest
endif

ifneq ($(filter x86_64, $(ARCH)),)
ALL_TARGETS   := initrd-themes initrd biostest initrd+modules boot-efi boot boot-themes $(COMMON_TARGETS) sax2
INSTSYS_PARTS := $(COMMON_INSTSYS_PARTS) sax2
BOOT_PARTS    := boot/* initrd biostest efi
endif

ifneq ($(filter ia64, $(ARCH)),)
ALL_TARGETS   := initrd-themes initrd initrd+modules boot-efi $(COMMON_TARGETS) sax2
INSTSYS_PARTS := $(COMMON_INSTSYS_PARTS) sax2
BOOT_PARTS    := initrd efi
endif

ifneq ($(filter s390 s390x, $(ARCH)),)
ALL_TARGETS   := initrd-themes initrd initrd+modules $(COMMON_TARGETS)
INSTSYS_PARTS := $(COMMON_INSTSYS_PARTS)
BOOT_PARTS    := initrd
endif

ifneq ($(filter ppc ppc64, $(ARCH)),)
ALL_TARGETS   := initrd-themes initrd initrd+modules+gefrickel $(COMMON_TARGETS) sax2
INSTSYS_PARTS := $(COMMON_INSTSYS_PARTS) sax2
BOOT_PARTS    :=
endif

THEMES        := openSUSE SLES SLED
DESTDIR       := images/instsys

export ARCH THEMES DESTDIR INSTSYS_PARTS BOOT_PARTS WITH_FLOPPY

.PHONY: all dirs base zeninitrd zenboot zenroot biostest initrd \
	boot boot-efi root rescue root+rescue sax2 gdb bind clean \
	boot-themes initrd-themes root-themes install \
	install-initrd mini-iso-rmlist debuginfo

all: $(ALL_TARGETS)
	@rm images/*.log

install:

dirs:
	@[ -d images ] || ( mkdir images ; cd images ; mkdir $(THEMES) )
	@[ -d tmp ] || mkdir tmp

base: dirs
	@[ -d tmp/base ] || nostrip=1 image=base fs=none bin/mk_image

zeninitrd: base
	initramfs=$${initramfs:-1} YAST_IS_RUNNING=1 theme=Zen filelist=zeninitrd bin/mk_initrd

zenboot: zeninitrd mboot
	theme=Zen initrd=large boot=isolinux memtest=no bin/mk_boot

zenroot: base
	theme=Zen fs=$${fs:-ext2} image=zenroot src=root fs=squashfs bin/mk_image

biostest: base
	libdeps=initrd,biostest image=biostest src=initrd fs=cpio.gz disjunct=initrd bin/mk_image

initrd: base
	libdeps=initrd image=initrd-base.gz tmpdir=initrd src=initrd filelist=initrd fs=cpio.gz bin/mk_image
	[ -s tmp/initrd/bin/bash ]

modules: base
	image=modules-config src=initrd fs=none bin/mk_image
	bin/mlist1
	bin/mlist2
	image=modules src=initrd fs=none bin/mk_image
	mkdir -p images/module-config/$${MOD_CFG:-default}
	ls -I module.config tmp/modules/modules | sed -e 's#.*/##' >images/module-config/$${MOD_CFG:-default}/module.list
	cp tmp/modules/modules/module.config images/module-config/$${MOD_CFG:-default}

initrd+modules: base
	image=modules-config src=initrd fs=none bin/mk_image
	bin/mlist1
	bin/mlist2
	rm -rf tmp/initrd/modules tmp/initrd/lib/modules
	mode=keep,add image=$${image:-initrd} tmpdir=initrd filelist=modules src=initrd fs=cpio bin/mk_image
	mkdir -p images/module-config/$${MOD_CFG:-default}
	ls -I module.config tmp/initrd/modules | sed -e 's#.*/##' >images/module-config/$${MOD_CFG:-default}/module.list
	cp tmp/initrd/modules/module.config images/module-config/$${MOD_CFG:-default}
	# now theme it
	for theme in $(THEMES) ; do \
	  cp images/$${image:-initrd} images/$$theme/$${image:-initrd} ; \
	  i=`pwd` ; ( cd tmp/initrd-$$theme ; find . | cpio --quiet -o -H newc -A -F $$i/images/$$theme/$${image:-initrd} ) ; \
	  gzip -9f images/$$theme/$${image:-initrd} ; mv images/$$theme/$${image:-initrd}.gz images/$$theme/$${image:-initrd} ; \
	done
	rm -f images/$${image:-initrd}

initrd+modules+gefrickel: base
	image=modules-config src=initrd fs=none bin/mk_image
	bin/mlist1
	bin/mlist2
	rm -rf tmp/initrd/modules tmp/initrd/lib/modules tmp/initrd_gefrickel
	# work on a copy to not modify the origial tree
	cp -a tmp/initrd tmp/initrd_gefrickel
	mode=keep,add image=$${image:-initrd} tmpdir=initrd_gefrickel filelist=modules src=initrd fs=none bin/mk_image
	mkdir -p images/module-config/$${MOD_CFG:-default}
	ls -I module.config tmp/initrd_gefrickel/modules | sed -e 's#.*/##' >images/module-config/$${MOD_CFG:-default}/module.list
	cp tmp/initrd_gefrickel/modules/module.config images/module-config/$${MOD_CFG:-default}
	./gefrickel tmp/initrd_gefrickel
	mode=keep image=$${image:-initrd} tmpdir=initrd_gefrickel src=initrd filelist=initrd fs=cpio bin/mk_image
	# now theme it
	for theme in $(THEMES) ; do \
	  cp images/$${image:-initrd} images/$$theme/$${image:-initrd} ; \
	  i=`pwd` ; ( cd tmp/initrd-$$theme ; find . | cpio --quiet -o -H newc -A -F $$i/images/$$theme/$${image:-initrd} ) ; \
	  gzip -9f images/$$theme/$${image:-initrd} ; mv images/$$theme/$${image:-initrd}.gz images/$$theme/$${image:-initrd} ; \
	done
	rm -f images/$${image:-initrd}

kernel: base
	image=vmlinuz-$${MOD_CFG:-default} src=initrd filelist=kernel kernel=kernel-$${MOD_CFG:-default} fs=dir bin/mk_image

boot-efi: base
	image=boot-efi src=boot filelist=efi fs=none bin/mk_image
	for theme in $(THEMES) ; do \
	  ln images/$$theme/initrd tmp/boot-efi/efi/boot/initrd ; \
	  bin/hdimage --size 500k --fit-size --chs 0 4 63 --part-ofs 0 --mkfs fat --add-files tmp/boot-efi/* tmp/boot-efi/.p* -- images/$$theme/efi ; \
	  rm -rf tmp/boot-efi/efi/boot/initrd ; \
	done

boot: base
	image=boot fs=dir bin/mk_image

root: base
	libdeps=root root_i18n=1 root_gfx=1 perldeps=root image=root bin/mk_image

rescue: base
	libdeps=rescue image=rescue bin/mk_image

root+rescue: base
	image=root+rescue fs=none bin/mk_image
	bin/common_tree --dst tmp/root+rescue tmp/rescue tmp/root
	mode=keep tmpdir=root+rescue/c image=common fs=squashfs bin/mk_image
	mode=keep tmpdir=root+rescue/1 image=rescue fs=squashfs bin/mk_image
	mode=keep tmpdir=root+rescue/2 image=root fs=squashfs bin/mk_image
	cp data/root/config images
	cat data/root/rpmlist tmp/base/yast2-trans-rpm.list >images/rpmlist

sax2: base
	libdeps=root,sax2 perldeps=root,sax2 image=sax2 src=root fs=squashfs disjunct=root bin/mk_image

gdb: base
	libdeps=root,gdb image=gdb src=root fs=squashfs disjunct=root bin/mk_image

bind: base
	libdeps=root,bind image=bind src=root fs=squashfs disjunct=root bin/mk_image

boot-themes: base
	for theme in $(THEMES) ; do \
	  theme=$$theme image=$$theme/boot tmpdir=boot-$$theme src=boot filelist=$$theme fs=dir bin/mk_image ; \
	done

initrd-themes: base
	for theme in $(THEMES) ; do \
	  theme=$$theme image=$$theme/install-initrd tmpdir=initrd-$$theme src=initrd filelist=$$theme fs=dir bin/mk_image ; \
	done

root-themes: base
	for theme in $(THEMES) ; do \
	  theme=$$theme image=$$theme/$$theme tmpdir=root-$$theme src=root filelist=$$theme fs=squashfs disjunct=root bin/mk_image ; \
	done

mini-iso-rmlist: base
	rm -f images/$@
	for i in \
	  common rescue root rpmlist branding initrd-xen vmlinuz-xen initrd-xenpae vmlinuz-xenpae efi \
	  $(THEMES) $(INSTSYS_PARTS) \
	; do echo boot/$(ARCH)/$$i >>images/$@ ; done

mboot:
	make -C src/mboot

add-xxx-key:
	gpg --homedir=gpg --no-default-keyring --keyring=./tmp/initrd/installkey.gpg --import ./gpg/pubring.gpg
	rm -f tmp/initrd/installkey.gpg~

debuginfo:
	./install.debuginfo

clean:
	-@make -C src/mboot clean
	-@make -C src/eltorito clean
	-@rm -rf images tmp
	-@rm -f `find -name '*~'`
	-@rm -rf /tmp/mk_initrd_* /tmp/mk_image_* 
	-@rm -rf data/initrd/gen data/boot/gen data/base/gen data/demo/gen
	-@rm -f gpg/trustdb.gpg gpg/random_seed

install:
	-@rm -rf $(DESTDIR)
	@mkdir -p $(DESTDIR)
	./install.$(ARCH)

install-initrd:
	-@rm -rf $(DESTDIR)
	@mkdir -p $(DESTDIR)/default
	cp images/initrd-base.gz $(DESTDIR)
	cp -a images/module-config/* $(DESTDIR)
	for theme in $(THEMES) ; do \
	  cp -a images/$$theme/install-initrd $(DESTDIR)/$$theme ; \
	done

