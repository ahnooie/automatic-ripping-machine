# Automatic Ripping Machine (ARM)

[![Build Status](https://travis-ci.org/automatic-ripping-machine/automatic-ripping-machine.svg?branch=v2_master)](https://travis-ci.org/automatic-ripping-machine/automatic-ripping-machine)

## Overview

Insert an optical disc (Blu-Ray, DVD, CD) and checks to see if it's audio, video (Movie or TV), or data, then rips it.

See: https://b3n.org/automatic-ripping-machine

## Features

- Detects insertion of disc using `udev`.
- Auto downloads keys_hashed.txt and KEYDB.cfg using robobrowser and tinydownloader.
- Determines disc type...
  - If video (Blu-Ray or DVD)
    - Retrieve title from disc or Windows Media MetaServices API to name the folder "movie title (year)" so that Plex or Emby can pick it up.
    - Determine if video is Movie or TV using OMDb API.
    - Rip using MakeMKV or HandBrake (can rip all features or main feature).
    - Eject disc and queue up Handbrake transcoding when done.
    - Transcoding jobs are asynchronusly batched from ripping.
    - Send notification when done via IFTTT or Pushbullet.
  - If audio (CD) - rip using abcde.
  - If data (Blu-Ray, DVD, or CD) - make an ISO backup.
- Headless, designed to be run from a server.
- Can rip from multiple-optical drives in parallel.
- HTML UI to interact with ripping jobs, view logs, etc.

## Usage

- Insert disc.
- Wait for disc to eject.
- Repeat.

## Requirements

- Ubuntu Server 18.04 (should work with other Linux distros) - Needs Multiverse and Universe repositories
- One or more optical drives to rip Blu-Rays, DVDs, and CDs
- Lots of drive space (I suggest using a NAS like FreeNAS) to store your movies

## Pre-Install (only if necessary)

If you have a new DVD drive that you haven't used before, some require setting the region before they can play anything.  Be aware most DVD players only let you change the region a handful (4 or 5?) of times then lockout any further changes.  If your region is already set or you have a region free DVD drive you can skip this step.

```bash
sudo apt install -y regionset
sudo regionset /dev/sr0
```

## Automatic Install Script For OpenMediaVault/Debian

**This MUST be run as root!**

**For the attended install use:**

```
sudo apt install -y wget
wget https://raw.githubusercontent.com/automatic-ripping-machine/automatic-ripping-machine/v2_master/scripts/debian-setup.sh
chmod +x debian-setup.sh
./debian-setup.sh
```

`reboot` to complete installation.

**For the silent install use**

```
apt -qqy install wget

wget https://raw.githubusercontent.com/automatic-ripping-machine/automatic-ripping-machine/v2_master/scripts/deb-install-quiet.sh
chmod +x deb-install-quiet.sh
./deb-install-quiet.sh
```

`reboot` to complete installation.

**Details about this script**

The script installs all dependencies, a service for the ARMui and the fstab entry for sr0, if you have more than one drive you will need to make the mount folder and insert any additional fstab entries.
The attended installer will do all of the necessary installs and deal with dependencies but will need user input.
The silent install will remove the need for the user to interact with the screen after intering the arm userpassword.

**The reason for the installer script ?**

The debian installer script has different commands than the ubuntu follow along commands. The reason being is that some of the commands that work on ubunutu do not work.
You can also run each line of the script in a console or ssh terminal.

## Manual Install

**Setup 'arm' user and ubuntu basics:**

Sets up graphics drivers, does Ubuntu update & Upgrade, gets Ubuntu to auto set up driver, and finally installs and setups up avahi-daemon

```bash
sudo apt update && sudo apt upgrade -y
### optional (was not required for me): sudo add-apt-repository ppa:graphics-drivers/ppa
sudo apt install -y avahi-daemon && sudo systemctl restart avahi-daemon
sudo apt install -y ubuntu-drivers-common && sudo ubuntu-drivers install
sudo reboot

# Installation of drivers seems to install a full gnome desktop, and it seems to set up hibernation modes.
# It is optional to run the below line (Hibernation may be something you want.)
#   sudo systemctl mask sleep.target suspend.target hibernate.target hybrid-sleep.target

sudo groupadd arm
sudo useradd -m arm -g arm -G cdrom
sudo passwd arm
# <enter new password>
```

**Set up repos and install dependencies**

```bash
sudo apt install -y git
sudo add-apt-repository ppa:heyarje/makemkv-beta
sudo add-apt-repository ppa:stebbins/handbrake-releases

NumOnly=$(cut -f2 <<< `lsb_release -r`) && case $NumOnly in "16.04" ) sudo add-apt-repository ppa:mc3man/xerus-media;; "18.04" ) sudo add-apt-repository ppa:mc3man/bionic-prop;; "20.04" ) sudo add-apt-repository ppa:mc3man/focal6;; *) echo "error in finding release version";; esac

sudo apt update && \
sudo apt install -y makemkv-bin makemkv-oss && \
sudo apt install -y handbrake-cli libavcodec-extra && \
sudo apt install -y abcde flac imagemagick glyrc cdparanoia && \
sudo apt install -y at && \
sudo apt install -y python3 python3-pip && \
sudo apt install -y libcurl4-openssl-dev libssl-dev && \
sudo apt install -y default-jre-headless && \
sudo apt install libdvd-pkg && \
sudo dpkg-reconfigure libdvd-pkg
```

**Install and setup ARM**

```bash
cd /opt
sudo mkdir -p arm
sudo chown arm:arm arm
sudo chmod 775 arm
sudo git clone https://github.com/automatic-ripping-machine/automatic-ripping-machine.git arm
sudo chown -R arm:arm arm
cd arm
sudo pip3 install -r requirements.txt
sudo cp /opt/arm/setup/51-automedia.rules /etc/udev/rules.d/
sudo ln -s /opt/arm/setup/.abcde.conf /home/arm/
sudo cp docs/arm.yaml.sample arm.yaml
sudo mkdir -p /etc/arm/
sudo ln -s /opt/arm/arm.yaml /etc/arm/
```

**Set up drives**

Create mount point for each dvd drive.
If you don't know the device name try running `dmesg | grep -i -E '\b(dvd|cd)\b'`.  The mountpoint needs to be /mnt/dev/<device name>.
So if your device name is `sr0`, set the mountpoint with this command:

```bash
sudo mkdir -p /mnt/dev/sr0
```

Repeat this for each device you plan on using with ARM.

Create entries in /etc/fstab to allow non-root to mount dvd-roms
Example (create for each optical drive you plan on using for ARM):
```
/dev/sr0  /mnt/dev/sr0  udf,iso9660  users,noauto,exec,utf8  0  0
```

**Configure ARM**

- Edit your "config" file (located at /opt/arm/arm.yaml) to determine what options you'd like to use.  Pay special attention to the 'directory setup' section and make sure the 'arm' user has write access to wherever you define these directories.

- Edit the music config file (located at /home/arm/.abcde.conf)

- To rip Blu-Rays after the MakeMKV trial is up you will need to purchase a license key or while MakeMKV is in BETA you can get a free key (which you will need to update from time to time) here:  https://www.makemkv.com/forum2/viewtopic.php?f=5&t=1053 and create /home/arm/.MakeMKV/settings.conf with the contents:

    app_Key = "insertlicensekeyhere"

- For ARM to identify movie/tv titles register for an API key at OMDb API: http://www.omdbapi.com/apikey.aspx and set the OMDB_API_KEY parameter in the config file.

After setup is complete reboot...

    reboot

Optionally if you want something more stable than master, you can download the latest release from the releases page.

**Email notifcations**

A lot of random problems are found in the sysmail, email alerting is a most effective method for debugging and monitoring.

I recommend you install postfix from here: http://mhawthorne.net/posts/2011-postfix-configuring-gmail-as-relay/

Then configure `/etc/aliases` e.g.:

```
root: my_email@gmail.com
arm: my_email@gmail.com
userAccount: my_email@gmail.com
```

Run below to pick up the aliases

```
sudo newaliases
```

## Upgrading to v2_master

If you wish to upgrade to v2_master instead of a clean install, these directions should get you there.

```bash
cd /opt/arm
sudo git checkout v2_master
sudo pip3 install -r requirements.txt
```

Backup config file and replace it with the updated config

```bash
mv arm.yaml arm.yaml.old
cp docs/arm.yaml.sample arm.yaml
```

There are new config parameters so review the new arm.yaml file

Make sure the 'arm' user has write permissions to the db directory (see your arm.yaml file for locaton). is writeable by the arm user.  A db will be created when you first run ARM.

Make sure that your rules file is properly **copied** instead of linked:

```
sudo rm /usr/lib/udev/rules.d/51-automedia.rules
sudo cp /opt/arm/setup/51-automedia.rules /etc/udev/rules.d/
```

Otherwise you may not get the auto-launching of ARM when a disc is inserted behavior
on Ubuntu 20.04.

Please log any issues you find.  Don't forget to run in DEBUG mode if you need to submit an issue (and log files).  Also, please note that you are running v2_master in your issue.

## Troubleshooting

When a disc is inserted, udev rules should launch a script (scripts/arm_wrapper.sh) that will launch ARM.  Here are some basic troubleshooting steps:

- Look for empty.log.
  - Everytime you eject the cdrom, an entry should be entered in empty.log like:
  ```
  [2018-08-05 11:39:45] INFO ARM: main.<module> Drive appears to be empty or is not ready.  Exiting ARM.
  ```
  - Empty.log should be in your logs directory as defined in your arm.yaml file.  If there is no empty.log file, or entries are not being entered when you eject the cdrom drive, then udev is not launching ARM correctly.  Check the instructions and make sure the symlink to 51-automedia.rules is set up right.  I've you've changed the link or the file contents you need to reload your udev rules with:
  ```
  sudo udevadm control --reload-rules
  ```

- Check ARM log files
  - The default location is /home/arm/logs/ (unless this is changed in your arm.yaml file) and is named after the dvd. These are very verbose.  You can filter them a little by piping the log through grep.  Something like
  ```
  cat <logname> | grep ARM:
  ```
    This will filter out the MakeMKV and HandBrake entries and only output the ARM log entries.
  - You can change the verbosity in the arm.yaml file.  DEBUG will give you more information about what ARM is trying to do.  Note: please run a rip in DEBUG mode if you want to post to an issue for assistance.
  - Ideally, if you are going to post a log for help, please delete the log file, and re-run the disc in DEBUG mode.  This ensures we get the most information possible and don't have to parse the file for multiple rips.

If you need any help feel free to open an issue.  Please see the above note about posting a log.

## Contributing

Pull requests are welcome.  Please see the [Contributing Guide](./CONTRIBUTING.md)

If you set ARM up in a different environment (harware/OS/virtual/etc), please consider submitting a howto to the [wiki](https://github.com/automatic-ripping-machine/automatic-ripping-machine/wiki).

## License

[MIT License](LICENSE)
