# Adding modules to the images

Adding modules is a two-step process. Both are needed and mandatory

1. Make sure your module is mentioned in ```etc/module.list```.

2. Make sure ```etc/module.config``` have a config entry for every module from 1.

The exact meaning and format of these and other relevant files is described below.

- File ```etc/module.list```

  Lists directories or single modules that could be useful for installation.

- File ```etc/module.config```

  Configuration for each module. The syntax for each line is described at the
  start of the file. To simplify things a bit, ```etc/module.config``` can have
  wildcard entries (e.g. ```kernel/drivers/scsi/.*```) that auto-create a
  config for all matching modules.

  The file is organized into sections. Some of the sections have a
  special meaning, but most of them exists just for historical reasons and are
  only relevant to put the modules into groups so you see them in linuxrc in
  the right place in case you have to load some manually. Thus, the
  ```[other]``` section is a safe option to add a module if in doubt.

  Most architectures will include the modules from all sections but
  ```[notuseful]```, ```[ppc]``` and ```[s390]```. Images for PowerPC use
  ```[ppc]``` instead of ```[scsi]``` & ```[net]``` as they want a particularly
  small initrd. Images for S390 _also_ use ```[s390]```. The file
  ```data/initrd/modules.file_list``` defines what sections are used.

  Last but not least. there is an ```[autoload]``` section for modules that
  must be loaded at startup but for one reason or the other aren't handled by
  udevd.

- File ```data/initrd/all_modules```

  Documentation file listing all the modules included in the kernel packages.
  It has no influence in the generation of images. This file is updated
  manually from time to time and is only used to help finding obsolete entries
  in the files described above.

A final note about modules dependencies. After the release of openSUSE 13.2,
the logic to auto-fulfill module dependencies changed. In the past you got a
warning and the module was dropped. That would be the behavior if you are using
an old branch. Now in Factory (i.e. the master branch) the required modules are
added automatically.
