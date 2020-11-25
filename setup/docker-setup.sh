#!/usr/bin/env bash
#
#
set -euo pipefail

SRCDIR="/opt/arm"
DATADIR="/srv/docker/arm"

git clone -b docker --depth=1 https://github.com/deekue/automatic-ripping-machine.git "$SRCDIR"
mkdir -p "$DATADIR"

cd "$SRCDIR"
docker build -t arm ${APT_PROXY:+--build-target ${APT_PROXY}} .

install setup/docker-arm.rules /etc/udev/rules.d/docker-arm.rules
udevadm control --reload
echo done.  insert a disc...
