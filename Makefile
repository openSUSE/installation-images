.PHONY: all dirs base zeninitrd zenboot zenroot biostest initrd \
	boot bootcd root rescue root+rescue sax2 gdb mboot clean

all: bootcd rescue root root+rescue gdb sax2
	@rm images/*.log

install:

dirs:
	@[ -d images ] || mkdir images
	@[ -d test ] || mkdir test
	@[ -d tmp ] || mkdir tmp

base: dirs
	@[ -d tmp/base ] || YAST_IS_RUNNING=1 bin/mk_base

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

gdb: dirs base
	nolibs=1 image=gdb src=root fs=squashfs disjunct=root bin/mk_image

mboot:
	make -C src/mboot

clean:
	-@make -C src/mboot clean
	-@make -C src/eltorito clean
	-@rm -rf images test tmp
	-@rm -f `find -name '*~'`
	-@rm -rf /tmp/mk_base_* /tmp/mk_initrd_* /tmp/mk_image_* 
	-@rm -rf data/initrd/gen data/boot/gen data/base/gen data/demo/gen
