#!/usr/bin/env bash
#
#

build_target="${1:-combined}"
image_name="arm-${build_target}"
image_label="${2:-latest}"
image_created="$(date -u +'%Y-%m-%dT%H:%M:%SZ')"
image_revision="$(git rev-parse --short HEAD)"
apt_proxy="${APT_PROXY:+--build-arg APT_PROXY=${APT_PROXY}}"

cd "$(dirname -- "${BASH_SOURCE[0]}")/.."

docker build ${apt_proxy} \
  --build-arg target="${build_target}" \
  --build-arg image_created="${image_created}" \
  --build-arg image_revision="${revision}" \
  -t "${image_name}:${image_label}" .
