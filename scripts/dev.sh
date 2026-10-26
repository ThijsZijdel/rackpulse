#!/bin/bash
source "$(dirname "$0")/lib.sh"

SIGN_ID=$(dev_identity) DEV_BUILD=1 scripts/build.sh
pkill -x Rackpulse || true
RACKPULSE_DEV=1 "$APP/Contents/MacOS/Rackpulse"
