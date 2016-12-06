# add correct product release package

if theme eq 'SLES'
  ReleasePackage = sles-release
elsif theme eq 'SLED'
  ReleasePackage = sled-release
else
  ReleasePackage = openSUSE-release
endif
<ReleasePackage>: nodeps

