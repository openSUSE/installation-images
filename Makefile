
# perl libraries & binaries
PLIBS	= AddFiles MakeFATImage MakeMinixImage ReadConfig
PBINS	= initrd_test mk_boot mk_initrd mk_initrd_test mk_root mk_root

.PHONY: all dirs initrd initrd_test boot boot_axp rescue\
        root demo modules html clean distdir install install_xx rdemo brescue
	rescue_cd mboot

all:

install:

distdir: clean
	@mkdir -p $(distdir)
	@tar -cf - . | tar -C $(distdir) -xpf -
	@find $(distdir) -depth -name CVS -exec rm -r {} \;

dirs:
	@[ -d images ] || mkdir images
	@[ -d test ] || mkdir test
	@[ -d tmp ] || mkdir tmp

initrd: dirs
	bin/mk_initrd

initrd_test: initrd
	bin/mk_initrd_test
	@echo "now, run bin/initrd_test"

boot: initrd mboot
	bin/mk_boot

boot_axp: initrd
	bin/mk_boot_axp

install_xx: initrd
	bin/mk_install_xx

root: dirs initrd
	bin/mk_root

demo: dirs
	bin/mk_demo

rdemo: dirs
	bin/mk_rdemo

rescue: dirs
	bin/mk_rescue

brescue: dirs
	bin/mk_brescue

rescue_cd: boot brescue rdemo
	bin/mk_rescue_cd

modules: dirs
	bin/mk_modules
	bin/mk_mod_disk

mboot:
	make -C src/mboot

html:
	@for i in $(PLIBS); do echo $$i; pod2html --noindex --title=$$i --outfile=doc/$$i.html lib/$$i.pm; done
	@for i in $(PBINS); do echo $$i; pod2html --noindex --title=$$i --outfile=doc/$$i.html bin/$$i; done
	@rm pod2html-dircache pod2html-itemcache

clean:
	-@make -C src/mboot clean
	-@umount test/initdisk/proc 2>/dev/null ; true
	-@umount test/initdisk/mnt 2>/dev/null ; true
	-@rm -rf images test tmp
	-@rm -f `find -name '*~'`
