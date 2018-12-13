# Adding packages and files

## Adding packages to the current (open)SUSE installation

Starting with openSUSE 13.1 and SLE12, the easiest way to include a package in
the installation system is modifying the `installation-images`
package in the Open Build Service. That package evaluates the dependencies and
automatically adds the required packages. Simply add the needed packages as a
BuildRequires dependency to the respective package and that's it.

## Modifying the list of files

The method explained above is only useful in some scenarios. It's not suitable
to update older systems, already released product or the rescue image. Moreover
it does not help if you want to remaster the images locally. Last but not least,
it only works for full packages, but it's often useful to include just a subset
of the files in a given package.

For every generated image there is a subdirectory in the `data` directory.
Among other several things, those directories contain files with the extension
`.file_list`. In order to fine tune the content of the generated images,
just modify the corresponding `.file_list` file according to the syntax
described [below](#format-of-the-file-list).

The output of `tree` shows the `.file_list` we're talking about.

```
#tree data -P "*.file_list"

data
├── base
│   └── base.file_list
├── boot
│   ├── boot.file_list
...
├── cd1
│   ├── cd1.file_list
...
├── initrd
...
│   ├── initrd.file_list
...

```

Keep in mind that in order to make sure the images still can be generated in the
Open Build Service, it's necessary to add the corresponding `BuildRequires`
to the `installation-images` package.

## Format of the file list

### Comments

Lines starting with `'#'` are comments, empty lines are ignored. Example:

```
 # some comment
```

### Including other files

You can include other files with the following syntax, where `FILE`
is relative to the `data/*/` tree.

```
include FILE
```

### Conditional sections

You can use `if/elsif/else/endif` with the following syntax.

```
if EXPRESSION
```

`EXPRESSION` is more or less a valid perl expression except that
variables don't have a starting `'$'` and are implicitly environment
variables. The only exceptions to this are `abuild` and `arch`.

Also, you can use `exists(PACKAGE)` to test for a specific package or
`exists(PACKAGE, FILE)` to test for a file in a package.

Note that the test for `FILE` is made in the unpacked rpm stored in the
internal cache. So unless it's an absolute path you can walk out of the root
tree. This can be used to check for the existence of rpm scripts (they are
cached one level up). Looking at the cache in `tmp/cache/PRODUCT/RPMNAME`
might make this clearer.

Examples:

```
if arch eq 'ppc' && theme eq 'SLES'
# ...
elsif arch eq 'sparc'
# ...
else
# ...
endif 

# only if package foo exists
if exists(foo)
# ...
endif

# only if package foo has a file /usr/bin/bar
if exists(foo, usr/bin/bar)
# ...
endif

# only if package foo has a postin script
if exists(foo, ../postin)
# ...
endif

```

### Environment variables

You can set environment variables:

```
MyVar1 = package-xxx
MyVar2 = "Value With Spaces"
```
and use them everywhere by putting the variable name between `'<'` and `'>'`:

```
  <MyVar1>:
  MyVar3 = <MyVar2>
```

### Packages

This syntax can be used to include files from a given package.

```
PACKAGE_NAME: [direct|ignore|nodeps|requires]
```

It unpacks the selected package into a temporary directory.

You can add tags (comma-separated) after the colon. The following tags
are supported:

  - requires: create a file `PACKAGE_NAME.requires` in the image root
  - nodeps: ignore package dependencies when solving
  - ignore: ignore package ('BuildIgnore')
  - direct: run rpm command to install the package

`PACKAGE_NAME` may be empty which can be used to tell the parser that
subsequent lines do not belong to any package.

`PACKAGE_NAME` can contain `'*'`s. In that case the latest package version
is used. If `PACKAGE_NAME` ends in `'~'` the last but one version is used.

If `PACKAGE_NAME` starts with a `'?'`, the package is optional.
This is a handy shortcut if you'd otherwise use an `if` with `exists()`.

If you use 'direct', basically `rpm -i PACKAGE_NAME` is run to install the
package. This means that all scripts are run and all files are unpacked. If
you don't need all files from the package you can still use 'r' to remove
the parts you don't need later.

Examples:

```
?grub:
glibc:
systemd: ignore
```

### Including packages matching a regexp

To include a group of packages matching a regexp, use `add_all`:

```
add_all PACKAGE_REGEXP:
```

Examples:

```
add_all skelcd-control-.*:
```

Note that you cannot associate any actions to such an entry directly. Use
templates (see below) if you don't want to install the packages as a whole.


### Actions

Several actions can be specified using the following syntax:

```
<action> <arg1> <arg2> ...
```

Do the specified action. `<action>` is one of these:

- Add the file/directory tree to the image:

```
  <args>
^ there's a space!
```

- Add a file/directory with a different name

```
m <old_name> <new_name>
```

- Same as 'm', but link files

```
L <old_name> <new_name>
```

- Same as 'm', but follows symlinks

```
a <old_name> <new_name>
```

- Add optional files (e.g. some modules in initrd)

```
M <old_name> <new_name>
```

- Add and gunzip files

```
g <src> <dst>
```

- Remove a file/directory tree

```
r <args>
```

- Create directories:

```
d <args>
```

- Create a named pipe:

```
n <name>
```

- Touch a file

```
t <args>
```

- Strip

```
S <args>
```

- Hard link (```<args>``` as for the ln command)

```
l <args>
```

- Symlink

```
s <args>
```

- Apply a patch from the `data/*/` tree. The patch **must not** contain
absolute path names!

```
p <patch>
```

- Copy package file (the rpm itself) to directory.

```
P <dir>
```

- chown/chmod files

```
c <perm> <owner> <group> <args>
```

- Make block device

```
  b <major> <minor> <name>
```

- Make char device

```
C <major> <minor> <name>
```

- Add some extra files. That is, add files not from packages but from
  the ```data/*/``` directory.

```
  x <src> <dst>
```

- Append ```<src>``` to ```<dst>```; ```<src>``` is from the
  ```data/*/``` directory.

```
  A <src> <dst>
```

- Execute a program/rpm-script. The program or script is run from within
  the 'base' environment. $PWD will be at the root of the filesystem which
  is currently built

```
  e <program> <arg1> <arg2> ...
  e <script>
```

- Execute a program/rpm-script (with chroot). The program/script is run within
  a chroot env. ```<script>``` must be one of the scripts given after the package
  name.

```
  E <program> <arg1> <arg2> ...
  E <script>
```

- Apply a perl regexp in a sed-like fashion to a file, `<regexp>` may
  contain white space but not `<file>`.
  If this is a multi line regexp (ends with `/s`) it is applied to
  the whole file. Otherwise the regexp is applied to each line.

  Note: `<file>` must not be an absolute symlink!

```
  R <regexp> <file>
```


- Search for a file ```<name>``` below ```<dir>``` and copy it to ```<dst>```
  (```<dst>``` may be omitted)

```
  f <dir> <name> <dst>
```

- search for a file `<name>` (in the local system!) below `<dir>` and
  copy it to `<dst>` (`<dst>` may be omitted)

```
  F <dir> <name> <dst>
```

- add files from the local system (This should be used only for testing!)

```
  X <src> <dst>
```

- Allow dangling symlink. Sometimes a symlink is ok because it points to a
  different image which can't be verified automatically.

```
  D <from> <to>
```

### Templates of packages

You can specify templates that are applied to groups of packages
automatically unless there is already some other valid entry for that
package. E.g.

```
TEMPLATE rubygem-.*:
  /usr/*/ruby/gems/*/gems/*/lib
  /usr/*/ruby/gems/*/specifications
```

The argument after TEMPLATE is a perl regexp matched agaist package names. If
the regexp is empty the TEMPLATE matches every package. This can be used
to formulate a default action for packages. E.g.

```
TEMPLATE:
  /
```

The package is matched against all templates in the order they appear in
the file list and the first match is used.

Note that the template should contain some action (it should not be
empty) because otherwise the matching will continue. If you don't need
any action use something inconspicuous, e.g. `'d .'`.

### Resolving dependencies

You can resolve dependencies and add the missing packages with the
AUTODEPS placeholder. The solver is run only if there is an AUTODEPS entry
somewhere.

```
AUTODEPS:
```

If you don't specify any actions in AUTODEPS, templates are appied to
each individual package.

