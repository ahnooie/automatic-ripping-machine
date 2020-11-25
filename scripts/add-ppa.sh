#!/bin/bash
#
# QaD script to add an Ubuntu PPA using only bash
# based on:
# /usr/bin/add-apt-repository
# /usr/lib/python3/dist-packages/softwareproperties/ppa.py
set -euo pipefail

LAUNCHPAD_PPA_API='https://launchpad.net/api/devel/%s/+archive/%s'
DEB_LINE="deb http://ppa.launchpad.net/%s/%s/%s %s main" #${owner} ${ppa_path} $codename 
SOURCE_FILENAME="/etc/apt/sources.list.d/%s-%s-%s-%s.list" #${owner} ${ppa_path}  $codename 
version_codename="$(sed -ne '/^VERSION_CODENAME=\(.*\)$/ s//\1/p' /etc/os-release)"
distro="$(sed -ne '/^ID=\(.*\)$/ s//\1/p' /etc/os-release)"
declare -a ppa_path_objs ppa_path_arr

shortcut="${1:?Usage: add-ppa.sh ppa:owner/path}"
ppa_shortcut="${shortcut#ppa:}"
owner_name="${ppa_shortcut%%/*}"
ppa_name="${ppa_shortcut#*/}"

# mangle shortcut path
readarray -t -d / ppa_path_objs < <(printf "%s\0" "${ppa_name}")
if [[ "${#ppa_path_objs[@]}" -lt 1 ]] ; then
  ppa_path_arr=(ubuntu ppa)
elif [[ "${#ppa_path_objs[@]}" -eq 1 ]] ; then
  ppa_path_arr=(ubuntu "${ppa_path_objs[@]}")
else
  ppa_path_arr=("${ppa_path_objs[@]}")
fi
ppa_path="$(IFS=/; echo "${ppa_path_arr[*]}")"

# get ppa info from lp
lp_url="$(printf "${LAUNCHPAD_PPA_API}" "~${owner_name}" "${ppa_path}")"
signing_key_fingerprint="$(wget -q --header "Accept: application/json" "${lp_url}" -O - \
  | sed -ne 's/^.*"signing_key_fingerprint": *"\([^"]*\)".*$/\1/p' )"
apt-key adv --keyserver keyserver.ubuntu.com --recv-keys "${signing_key_fingerprint}"
source_file="$(printf "${SOURCE_FILENAME}" ${owner_name} ${distro} ${ppa_name//\//-} ${version_codename})" 
printf "${DEB_LINE}" ${owner_name} ${ppa_name} ${distro} ${version_codename} \
  > "${source_file}"
echo "created ${source_file}"
