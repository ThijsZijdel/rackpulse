#!/bin/bash
source "$(dirname "$0")/lib.sh"

site=${SITE_URL:-https://tools-cdn.en3sis.com/tools/rackpulse}
prefix=${R2_PREFIX:-tools/rackpulse}

r2_check

release=$(agent_version)
out=dist/agent/$release
files=(install.sh rackpulse-agent-linux-amd64 rackpulse-agent-linux-arm64 SHA256SUMS)
for name in "${files[@]}"; do
  if [ ! -f "$out/$name" ]; then
    echo "$out/$name is missing. Run make agent first"
    exit 1
  fi
done
(cd "$out" && shasum -a 256 -c SHA256SUMS >/dev/null) || {
  echo "Checksums in $out/SHA256SUMS do not match. Run make agent again"
  exit 1
}

content_type() {
  case "$1" in
    install.sh) echo "text/x-shellscript; charset=utf-8" ;;
    SHA256SUMS) echo "text/plain; charset=utf-8" ;;
    *) echo application/octet-stream ;;
  esac
}

echo "Uploading rackpulse-agent $release to $site/agent"
r2_setup

for name in "${files[@]}"; do
  put "$out/$name" "agent/$release/$name" "$(content_type "$name")" "public, max-age=31536000, immutable"
done
for name in "${files[@]}"; do
  put "$out/$name" "agent/$name" "$(content_type "$name")" "public, max-age=300"
done
