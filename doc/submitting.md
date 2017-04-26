## Submitting changes to SUSE Build Service

Submissions are managed by a SUSE internal [jenkins](https://jenkins.io) node in the InstallTools tab.

Each time a new commit is integrated into the master branch of the repository,
a new submit request is created to the openSUSE Build Service. The devel project
is [system:install:head](https://build.opensuse.org/package/show/system:install:head/installation-images).

For maintained branches, the package is submitted to a devel project but the final submission
must be triggered manually.

`*.changes` and version numbers are auto-generated from git commits, you don't have to worry about this.

The spec file is maintained in the Build Service only. If you need to change it for the `master` branch,
submit to the
[devel project](https://build.opensuse.org/package/show/system:install:head/installation-images)
in the build service directly.

The current names of the devel projects for other branches can be seen in the jenkins logs.

Development happens mainly in the `master` branch. The branch is used for all current products.

In rare cases branching was unavoidable:

* branch `sl_11.1`: SLE 11 SP4.
* branch `sle12`: SLE 12.
* branch `sle12-sp2`: SLE 12 SP2.

You can find more information about the changes auto-generation and the
tools used for jenkis submissions in the [linuxrc-devtools
documentation](https://github.com/openSUSE/linuxrc-devtools#opensuse-development).

