ARCH := $(shell uname -m)
ifneq ($(filter i386 i486 i586 i686, $(ARCH)),)
ARCH := i386
endif

GIT2LOG := $(shell if [ -x ./git2log ] ; then echo ./git2log --update ; else echo true ; fi)
GITDEPS := $(shell [ -d .git ] && echo .git/HEAD .git/refs/heads .git/refs/tags)
VERSION := $(shell $(GIT2LOG) --version VERSION ; cat VERSION)
BRANCH  := $(shell [ -d .git ] && git branch | perl -ne 'print $$_ if s/^\*\s*//')
PREFIX  := installation-images-$(VERSION)

COMMON_TARGETS	     := rescue root root+rescue bind gdb mini-iso-rmlist
COMMON_INSTSYS_PARTS := config rpmlist root common rescue bind gdb

ifneq ($(filter i386, $(ARCH)),)
ALL_TARGETS   := initrd-themes initrd initrd+modules+gefrickel boot boot-themes $(COMMON_TARGETS) zenroot
INSTSYS_PARTS := $(COMMON_INSTSYS_PARTS)
BOOT_PARTS    := boot/* initrd
endif

ifneq ($(filter x86_64, $(ARCH)),)
ALL_TARGETS   := initrd-themes initrd initrd+modules+gefrickel boot-grub2-efi boot boot-themes $(COMMON_TARGETS) rescue-server zenroot
INSTSYS_PARTS := $(COMMON_INSTSYS_PARTS)
BOOT_PARTS    := boot/* initrd efi
endif

ifneq ($(filter ia64, $(ARCH)),)
ALL_TARGETS   := initrd-themes initrd initrd+modules boot-efi $(COMMON_TARGETS)
INSTSYS_PARTS := $(COMMON_INSTSYS_PARTS)
BOOT_PARTS    := initrd efi
endif

ifneq ($(filter s390 s390x, $(ARCH)),)
ALL_TARGETS   := initrd-themes initrd initrd+modules $(COMMON_TARGETS)
INSTSYS_PARTS := $(COMMON_INSTSYS_PARTS)
BOOT_PARTS    := initrd
endif

ifneq ($(filter aarch64, $(ARCH)),)
ALL_TARGETS   := initrd-themes initrd initrd+modules+gefrickel boot boot-grub2-efi boot-themes $(COMMON_TARGETS)
INSTSYS_PARTS := $(COMMON_INSTSYS_PARTS)
BOOT_PARTS    := boot/* initrd efi
endif

ifneq ($(filter ppc ppc64 ppc64le, $(ARCH)),)
ALL_TARGETS   := initrd-themes initrd initrd+modules+gefrickel boot-grub2-powerpc $(COMMON_TARGETS)
INSTSYS_PARTS := $(COMMON_INSTSYS_PARTS)
BOOT_PARTS    :=
endif

# THEMES must be a single value
THEMES        := openSUSE
DESTDIR       := images/instsys

ifneq ($(filter i386 x86_64, $(ARCH)),)
# needs SLES themes
# THEMES        += Zen
endif

export ARCH THEMES DESTDIR INSTSYS_PARTS BOOT_PARTS WITH_FLOPPY

.PHONY: all dirs base fbase biostest initrd \
	boot boot-efi root rescue root+rescue gdb bind clean \
	boot-themes initrd-themes root-themes zenroot install \
	install-initrd mini-iso-rmlist debuginfo cd1

all: $(ALL_TARGETS) VERSION changelog
	@rm images/*.log

changelog: $(GITDEPS)
	$(GIT2LOG) --changelog changelog

version.h: VERSION
	@echo "#define LXRC_VERSION \"`cut -d. -f1-2 VERSION`\"" >$@
	@echo "#define LXRC_FULL_VERSION \"`cat VERSION`\"" >>$@

install:

dirs:
	@[ -d images ] || ( mkdir images ; cd images ; mkdir $(THEMES) )
	@[ -d tmp ] || mkdir tmp

base: dirs
	@[ -d tmp/base ] || theme=$(THEMES) nostrip=1 libdeps=base image=base fs=none bin/mk_image

fbase: dirs
	theme=$(THEMES) nostrip=1 libdeps=base image=base fs=none bin/mk_image

biostest: base
	theme=$(THEMES) libdeps=initrd,biostest image=biostest src=initrd fs=cpio.xz disjunct=initrd bin/mk_image

initrd: base
	theme=$(THEMES) libdeps=initrd image=initrd-base.xz tmpdir=initrd src=initrd filelist=initrd fs=cpio.xz bin/mk_image
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
	mode=add tmpdir=initrd image=modules src=initrd fs=none bin/mk_image
	mkdir -p images/module-config/$${MOD_CFG:-default}
	ls -I module.config tmp/initrd/modules | sed -e 's#.*/##' >images/module-config/$${MOD_CFG:-default}/module.list
	cp tmp/initrd/modules/module.config images/module-config/$${MOD_CFG:-default}
	mode=keep image=$(THEMES)/$${image:-initrd} tmpdir=initrd fs=cpio.xz bin/mk_image

initrd+modules+gefrickel: base
	image=modules-config src=initrd fs=none bin/mk_image
	bin/mlist1
	bin/mlist2
	rm -rf tmp/initrd/modules tmp/initrd/lib/modules tmp/initrd_gefrickel
	# work on a copy to not modify the origial tree
	cp -a tmp/initrd tmp/initrd_gefrickel
	mode=add tmpdir=initrd_gefrickel image=modules src=initrd fs=none bin/mk_image
	mkdir -p images/module-config/$${MOD_CFG:-default}
	ls -I module.config tmp/initrd_gefrickel/modules | sed -e 's#.*/##' >images/module-config/$${MOD_CFG:-default}/module.list
	cp tmp/initrd_gefrickel/modules/module.config images/module-config/$${MOD_CFG:-default}
	./gefrickel tmp/initrd_gefrickel
	mode=keep image=$(THEMES)/$${image:-initrd} tmpdir=initrd_gefrickel fs=cpio.xz bin/mk_image

kernel: base
	image=vmlinuz-$${MOD_CFG:-default} src=initrd filelist=kernel kernel=kernel-$${MOD_CFG:-default} fs=dir bin/mk_image

boot-efi: base
	theme=$(THEMES) image=boot-efi src=boot filelist=efi fs=none bin/mk_image
	for theme in $(THEMES) ; do \
	  ln images/$$theme/initrd tmp/boot-efi/efi/boot/initrd ; \
	  bin/hdimage --size 500k --fit-size --chs 0 4 63 --part-ofs 0 --mkfs fat --add-files tmp/boot-efi/* tmp/boot-efi/.p* -- images/$$theme/efi ; \
	  rm -rf tmp/boot-efi/efi/boot/initrd ; \
	done

boot-grub2-efi: base
	for theme in $(THEMES) ; do \
	  theme=$$theme image=$$theme/EFI tmpdir=boot-efi-$$theme src=boot filelist=grub2-efi fs=dir bin/mk_image ; \
	  bin/hdimage --size 500k --fit-size --chs 0 4 63 --part-ofs 0 --mkfs fat --add-files tmp/boot-efi-$$theme/* tmp/boot-efi-$$theme/.p* -- images/$$theme/efi ; \
	done

boot-grub2-powerpc: base
	for theme in $(THEMES) ; do \
	  mkdir -p images/$$theme/boot/$(ARCH) ; \
	  theme=$$theme tmpdir=boot-grub2-ieee1275-$(ARCH)-$$theme nostrip=1 image=$$theme/grub2-ieee1275 src=boot filelist=grub2-powerpc fs=dir bin/mk_image ; \
	done

boot: base
	theme=$(THEMES) image=boot fs=dir bin/mk_image

root: base
	theme=$(THEMES) libdeps=root image=root bin/mk_image

rescue: base
	theme=$(THEMES) libdeps=rescue image=rescue bin/mk_image

rescue-server:
	theme=$(THEMES) image=rescue-server src=rescue filelist=rescue-server fs=squashfs bin/mk_image

root+rescue: base
	image=root+rescue fs=none bin/mk_image
	bin/common_tree --dst tmp/root+rescue tmp/rescue tmp/root
	mode=keep tmpdir=root+rescue/c image=common fs=squashfs bin/mk_image
	mode=keep tmpdir=root+rescue/1 image=rescue fs=squashfs bin/mk_image
	mode=keep tmpdir=root+rescue/2 image=root fs=squashfs bin/mk_image
	cp data/root/config images
	cat data/root/rpmlist tmp/base/yast2-trans-rpm.list >images/rpmlist

gdb: base
	libdeps=root,gdb image=gdb src=root fs=squashfs disjunct=root bin/mk_image

bind: base
	libdeps=root,bind image=bind src=root fs=squashfs disjunct=root bin/mk_image

snapper: base
	libdeps=root,snapper image=snapper src=root fs=squashfs disjunct=root bin/mk_image

boot-themes: base
	for theme in $(THEMES) ; do \
	  theme=$$theme image=$$theme/boot tmpdir=boot-$$theme src=boot filelist=theme fs=dir bin/mk_image ; \
	done

initrd-themes: base
	mkdir -p images/$(THEMES)/install-initrd

root-themes: base
	for theme in $(THEMES) ; do \
	  theme=$$theme image=$$theme/$$theme tmpdir=root-$$theme src=root filelist=theme fs=squashfs bin/mk_image ; \
	done

zenroot:
	theme=$(THEMES) libdeps=zenroot alternatives=1 image=zenroot src=root fs=squashfs bin/mk_image

cd1: base
	mkdir -p data/cd1/gen
	rm -f data/cd1/gen/rpm.file_list
	for i in `cat images/rpmlist` ; do \
	  echo -e "$$i:\n  X <rpm_file> CD1/boot/<arch>\n" >> data/cd1/gen/rpm.file_list; \
	done
	theme=$(THEMES) nostrip=1 image=cd1 fs=none sw 0 bin/mk_image
	cp -a images/instsys/CD1 tmp/cd1
	rm -f tmp/cd1/CD1/boot/*/rpmlist
	cp -a images/instsys/branding/$(THEMES)/CD1 tmp/cd1

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

archive: changelog
	@if [ ! -d .git ] ; then echo no git repo ; false ; fi
	mkdir -p package
	git archive --prefix=$(PREFIX)/ $(BRANCH) > package/$(PREFIX).tar
	tar -r -f package/$(PREFIX).tar --mode=0664 --owner=root --group=root --mtime="`git show -s --format=%ci`" --transform='s:^:$(PREFIX)/:' VERSION changelog
	xz -f package/$(PREFIX).tar

clean:
	-@make -C src/mboot clean
	-@make -C src/eltorito clean
	-@rm -rf images tmp
	-@rm -f `find -name '*~'`
	-@rm -rf /tmp/mk_initrd_* /tmp/mk_image_* 
	-@rm -rf data/initrd/gen data/boot/gen data/base/gen data/cd1/gen package
	-@rm -f gpg/trustdb.gpg gpg/random_seed

install:
	-@rm -rf $(DESTDIR)
	@mkdir -p $(DESTDIR)
	./install.$(ARCH)
	@mkdir -p $(DESTDIR)/usr/share/debuginfodeps
	./debuginfodeps root

install-initrd:
	-@rm -rf $(DESTDIR)
	@mkdir -p $(DESTDIR)/default
	cp images/initrd-base.xz $(DESTDIR)
	cp -a images/module-config/* $(DESTDIR)
	for theme in $(THEMES) ; do \
	  cp -a images/$$theme/install-initrd $(DESTDIR)/$$theme ; \
	done

