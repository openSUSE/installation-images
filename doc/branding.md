# How the branding works

To add a new theme, add a new `Theme` section to etc/config. Example for theme
`SLES`:

```sh
[Theme SLES]
image       = 600			# memory limit for loading inst-sys: 600 MB
# other entries are branding prefixes or suffixes to branding-related packages
release     = sles			# sles-release.rpm
skelcd      = sles			# skelcd-sles.rpm
skelcd_ctrl = SLES			# skelcd-control-SLES.rpm
gfxboot     = SLE			# gfxboot-branding-SLE.rpm
grub2       = SLE			# grub2-branding-SLE.rpm
plymouth    = SLE			# plymouth-branding-SLE.rpm
systemd     = SLE			# systemd-presets-branding-SLE.rpm
yast        = SLE			# yast2-theme-SLE.rpm
```

Then add an appropriate theme section to `installation-images.spec`.

Note that the actual product name and path for driver updates are
auto-generated from `/usr/lib/os-release`. For completely new products
you'll have to adjust `lib/ReadConfig.pm::get_version_info` and please also
leave a sample of the `os-release` file in `etc/os_sample.txt`.
