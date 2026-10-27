#!/bin/bash
source "$(dirname "$0")/lib.sh"

require SITE_URL
site=$SITE_URL
prefix=${R2_PREFIX:-}
prefix=${prefix%/}

r2_check

release=$(version)
image=$(release_dir "$release")/Rackpulse-$release.dmg
if [ ! -f "$image" ] || ! grep -q "Rackpulse-$release.dmg" dist/appcast.xml 2>/dev/null; then
  echo "Version $release is not notarized yet. Run make notarize first"
  exit 1
fi

echo "Uploading Rackpulse $release to $site"
r2_setup

for file in dist/Rackpulse-*/*.dmg dist/Rackpulse-*/*.delta; do
  if [ -f "$file" ]; then
    put "$file" "download/$(basename "$file")" application/octet-stream "public, max-age=31536000, immutable"
  fi
done
put "$image" download/Rackpulse.dmg application/x-apple-diskimage "public, max-age=300"
put dist/appcast.xml appcast.xml application/xml "public, max-age=300"
