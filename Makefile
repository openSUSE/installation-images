
# perl libraries & binaries
PLIBS	= AddFiles MakeFATImage MakeMinixImage ReadConfig
PBINS	= initrd_test mk_boot mk_initrd mk_initrd_test mk_root mk_yast2\
          mk_yast2_cd mk_yast2_nfs

.PHONY: all dirs initrd initrd_test initrd2 initrd2_test boot boot2 boot_axp\
        yast2 html clean distdir install

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

initrd2: dirs
	bin/mk_initrd2

initrd2_test: initrd2
	bin/mk_initrd2_test
	@echo "now, run bin/initrd2_test"

boot: initrd
	bin/mk_boot

boot2: initrd2
	bin/mk_boot2

boot_axp: initrd
	bin/mk_boot_axp

yast2: dirs initrd2
	bin/mk_yast2

html:
	@for i in $(PLIBS); do echo $$i; pod2html --noindex --title=$$i --outfile=doc/$$i.html lib/$$i.pm; done
	@for i in $(PBINS); do echo $$i; pod2html --noindex --title=$$i --outfile=doc/$$i.html bin/$$i; done
	@rm pod2html-dircache pod2html-itemcache

clean:
	-@umount test/initdisk/proc 2>/dev/null ; true
	-@umount test/initdisk/mnt 2>/dev/null ; true
	-@rm -rf images test tmp
	-@rm -f *~ */*~ */*/*~
