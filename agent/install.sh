#!/bin/sh
set -eu

main() {
  base=${RACKPULSE_AGENT_URL:-https://tools-cdn.en3sis.com/tools/rackpulse/agent}

  if [ "$(uname -s)" != "Linux" ]; then
    echo "The Rackpulse agent runs on Linux servers. Run this command on the server, not on this computer." >&2
    exit 1
  fi

  if [ "$(id -u)" -ne 0 ]; then
    echo "Run this script as root, for example: curl -fsSL $base/install.sh | sudo sh -s -- --pair <key>" >&2
    exit 1
  fi

  machine=$(uname -m)
  case "$machine" in
    x86_64 | amd64) arch=amd64 ;;
    aarch64 | arm64) arch=arm64 ;;
    *)
      echo "Unsupported architecture: $machine. The Rackpulse agent runs on x86_64 and arm64" >&2
      exit 1
      ;;
  esac

  if ! command -v sha256sum >/dev/null 2>&1; then
    echo "sha256sum is missing. Install coreutils and run the command again" >&2
    exit 1
  fi

  name=rackpulse-agent-linux-$arch
  tmp=$(mktemp -d)
  trap 'rm -rf "$tmp"' EXIT
  trap 'exit 1' HUP INT TERM

  echo "Downloading $name from $base"
  fetch "$base/$name" "$tmp/rackpulse-agent"
  fetch "$base/SHA256SUMS" "$tmp/SHA256SUMS"

  expected=$(awk -v file="$name" '$2 == file || $2 == "*" file { print $1 }' "$tmp/SHA256SUMS")
  actual=$(sha256sum "$tmp/rackpulse-agent" | awk '{ print $1 }')
  if [ -z "$expected" ] || [ "$expected" != "$actual" ]; then
    echo "Checksum check failed for $name. The download is incomplete or changed. Try again" >&2
    exit 1
  fi

  chmod 755 "$tmp/rackpulse-agent"
  "$tmp/rackpulse-agent" install "$@" </dev/null
}

fetch() {
  if command -v curl >/dev/null 2>&1; then
    curl -fsSL --retry 3 -o "$2" "$1"
  elif command -v wget >/dev/null 2>&1; then
    wget -q -O "$2" "$1"
  else
    echo "Install curl or wget and run the command again" >&2
    exit 1
  fi
}

main "$@"
