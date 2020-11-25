#!/bin/bash
#
#
set -euo pipefail

DOCKER_IMAGE="arm:latest"
CONTAINER_NAME="arm"
CONTAINER_VOLUME="/srv/docker/arm:/home/arm"
CONTAINER_RESTART="on-failure:3"
ARM_UID="115" # "$(id -u plex)"
ARM_GID="120" # "$(id -g plex)"

# exit if udev ID_CDROM_MEDIA properties not available yet
# avoid running too early
if [[ -z "${!ID_CDROM_MEDIA_*}" ]] ; then
  #echo "$(date) disk not ready/identified yet" >> /tmp/docker_arm_wrapper.log
  exit 0
fi

# fork to let udev keep running
if [[ "${1:-}" != "fork" ]] ; then
  #{ "$0" fork "$*" > /dev/null 2>&1 < /dev/null & } &
  echo "$0 fork $@" | at -M now # systemd udev hates children
  exit 0
else
  # get rid of "fork" arg
  shift
fi

DEVNAME="$1"
if [[ -z "${DEVNAME}" ]] ; then
  echo "Usage: $(basename -- "$0") <device>" | logger -t ARM -s
  exit 1
fi
if [[ ! -b "${DEVNAME}" && -b "/dev/${DEVNAME}" ]] ; then
  DEVNAME="/dev/${DEVNAME}"
fi

function findGenericDevice {
  if command -v lsscsi > /dev/null ; then
    SG_DEV="$(lsscsi -g | sed -ne '/\/dev\/sr[0-9]/ s#.*\(/dev/sg[0-9]*\) *#\1#p')"
    if [[ -n "${SG_DEV}" ]] ; then
      echo "Found generic device for ${DEVNAME}: ${SG_DEV}" | logger -t ARM
      echo "${SG_DEV}"
    fi
  fi
}

function runArmContainer {
  SG_DEV="$(findGenericDevice)"
  if [[ -n "${SG_DEV}" ]] ; then
    SG_DEV_ARG="--device=${SG_DEV}:/dev/sg0"
  fi
  echo "Starting on ${DEVNAME} ${SG_DEV}" | logger -t ARM
  # mounting a device in a container requires:
  #  capability: SYS_ADMIN
  #  security option: apparmor:unconfined
  docker run -d \
    --device="${DEVNAME}:/dev/sr0" ${SG_DEV_ARG} \
    -e UID="${ARM_UID}" -e GID="${ARM_GID}" \
    -v "${CONTAINER_VOLUME}" \
    --cap-add SYS_ADMIN \
    --security-opt apparmor:unconfined \
    --restart "${CONTAINER_RESTART}" \
    --name "${CONTAINER_NAME}" \
    "${DOCKER_IMAGE}" \
    | logger -t ARM
}

function startArmContainer {
  echo "Starting stopped container ${CONTAINER_NAME}" | logger -t ARM
  docker start "${CONTAINER_NAME}" | logger -t ARM
}

function startArmRip {
  # get info from udev to pass into the Docker container
  if [[ -z "${!ID_CDROM_MEDIA_*}" ]] ; then
    eval "$(udevadm info --query=env --export "${DEVNAME}")"
  fi
  local disctype="$(echo ${!ID_CDROM_MEDIA_*} \
    | sed -nE '/.*(ID_CDROM_MEDIA_(BD|DVD|TRACK_COUNT_AUDIO)).*/ s//\1=1/p' )"
  local label_flag="${ID_FS_LABEL:+-l ID_FS_LABEL=${ID_FS_LABEL}}"
  if [[ -z "${disctype}" ]] ; then 
    echo "disctype not detected from udev, not ripping" >&2
    exit 1
  fi

  echo "Starting rip" | logger -t ARM
  docker exec -i \
    -u "${ARM_UID}" \
    -w /home/arm \
    "${CONTAINER_NAME}" \
    python3 /opt/arm/arm/ripper/main.py \
      -d sr0 -t ${disctype} ${label_flag}  \
    | logger -t ARM
}

# start ARM container, if not running, for WebUI
container_status="$(docker container ls -l -f name="${CONTAINER_NAME}" --format '{{json .Status}}')"
case "${container_status//\"}" in
  Up*)
    echo "container '${CONTAINER_NAME}' status: ${container_status}" | logger -t ARM
    ;;
  Exited*)
    startArmContainer
    ;;
  *)
    runArmContainer
    ;;  
esac

# start the rip inside the same container
startArmRip
