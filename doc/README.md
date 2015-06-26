# (open)SUSE installation images

Scripts and tools to generate the disk images used during installation
(inst-sys) and the rescue disk images for openSUSE and SUSE.

## Generating the images locally

To build a new image, you have to:

* be root
* put the installation-images directory on a *local* file system (ie. not NFS)

Then you can run ```make``` to build all parts.

The images are stored in the 'image' directory, the contents of the images
is in the 'tmp' directory.

```make install``` will gather the images an put them into the 'instsys' dir.

For testing purposes there is a make target 'cd1' that builds a complete
tree as it's used on our media.

## Configuring the generation of images

The exact behavior of ```make``` can be influenced by several environment
variables. For a full description of these variables and how they affect each
image, check the [configoptions.md](configoptions.md) file.

## Committing changes to (open)SUSE

**NOTE: we discussed here something about a hack to exclude branding in some cases**

Every time a new commit is integrated into the master branch of the repository,
a new submit request is created in the openSUSE Build Service for the
[corresponding package](https://build.opensuse.org/package/show/openSUSE:Factory/installation-images-openSUSE).

A similar procedure is set in other branches of this repository, making possible
to submit changes to other products and versions as well.

* Branch ```sl_11.1``` SUSE Enterprise 11 SP4.
* Branch ```sle12``` SUSE Enterprise 12.
* Branch ```master``` Factory and SUSE Enterprise 12 SP1.

## Anatomy of the images

After a successful execution of ```make``` the directory ```images/``` will
contain several subdirectories and files. This structure is described in the
[images.md](images.md) file.

## FAQ

* How to make sure a driver is available in the installation/rescue system?
  Check the [modules.md](modules.md) file.

* How to add a package or one of its file to the image?
  Check the [files.md](files.md) file.

* How the branding works?
  Check the [branding.md](branding.md) file

**TODO FAQ: compression algorithm, linemode, fonts**
