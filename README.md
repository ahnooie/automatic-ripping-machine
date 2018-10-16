# Automatic Ripping Machine (ARM)

[![Build Status](https://travis-ci.org/automatic-ripping-machine/automatic-ripping-machine.svg?branch=v2_master)](https://travis-ci.org/automatic-ripping-machine/automatic-ripping-machine)

## Note if upgrading from v2_master to v2_fixes

The v2_fixes branch currently has a fix for #210 which changes ARM to launch a wrapper script and removed all usage of Systemd.  If you previously had
v2_master installed and checkout this branch (or were on a previous version of v2_fixes), then you need to make a couple of manual changes to update Udev
to point to the wrapper script.

After updating your local v2_fixes branch run the following command:
```bash
sudo udevadm control --reload-rules
```
You might also want to make sure your symlink to 51-automedia.rules is still in tact.

Finally, although it's technically not necessary, you probably should remove all remnants of the systemd configuration.  See instructions here:
https://superuser.com/questions/513159/how-to-remove-systemd-services


## Overview

Insert an optical disc (Blu-Ray, DVD, CD) and checks to see if it's audio, video (Movie or TV), or data, then rips it.

See: https://b3n.org/automatic-ripping-machine


## Features

- Detects insertion of disc using udev
- Auto downloads keys_hashed.txt and KEYDB.cfg using robobrowser and tinydownloader
- Determines disc type...
  - If video (Blu-Ray or DVD)
    - Grabs Latest MakeMKV key
    - Retrieve title from disc or Windows Media MetaServices API to name the folder "movie title (year)" so that Plex or Emby can pick it up
    - Determine if video is Movie or TV using OMDb API
    - Rip using MakeMKV or HandBrake (can rip all features or main feature)
    - Eject disc and queue up Handbrake transcoding when done
    - Transcoding jobs are asynchronusly batched from ripping
    - Send notification when done via IFTTT or Pushbullet
  - If audio (CD) - rip using abcde
  - If data (Blu-Ray, DVD, or CD) - make an ISO backup
- Headless, designed to be run from a server
- Can rip from multiple-optical drives in parallel


## Requirements

- Ubuntu Server 18.04 (should work with other Linux distros)
- One or more optical drives to rip Blu-Rays, DVDs, and CDs
- Lots of drive space (I suggest using a NAS like FreeNAS) to store your movies

## Pre-Install (only if necessary)

If you have a new DVD drive that you haven't used before, some require setting the region before they can play anything.  Be aware most DVD players only let you change the region a handful (4 or 5?) of times then lockout any further changes.  If your region is already set or you have a region free DVD drive you can skip this step.

```bash
sudo apt-get install regionset
sudo regionset /dev/sr0
```

## Install

**Setup 'arm' user:**

```bash
sudo groupadd arm
sudo useradd -m arm -g arm -G cdrom
sudo passwd arm 
  <enter new password>
```

**Set up repos and install dependencies**

```bash
sudo apt-get install git
sudo add-apt-repository ppa:heyarje/makemkv-beta
sudo add-apt-repository ppa:stebbins/handbrake-releases
```
For Ubuntu 16.04 `sudo add-apt-repository ppa:mc3man/xerus-media`  
For Ubuntu 18.04 `sudo add-apt-repository ppa:mc3man/bionic-prop`  

```bash
sudo apt update
sudo apt install makemkv-bin makemkv-oss
sudo apt install handbrake-cli libavcodec-extra
sudo apt install abcde flac imagemagick glyrc cdparanoia
sudo apt install at
sudo apt install python3 python3-pip
sudo apt-get install libcurl4-openssl-dev libssl-dev
sudo apt-get install libdvd-pkg
sudo dpkg-reconfigure libdvd-pkg
sudo apt install default-jre-headless
```

**Install and setup ARM**

```bash
cd /opt
sudo mkdir arm
sudo chown arm:arm arm
sudo chmod 775 arm
sudo git clone https://github.com/automatic-ripping-machine/automatic-ripping-machine.git arm
cd arm
# TODO: Remove below line before merging to master
git checkout v2_master
sudo pip3 install -r requirements.txt 
sudo ln -s /opt/arm/setup/51-automedia.rules /lib/udev/rules.d/
sudo ln -s /opt/arm/setup/.abcde.conf /home/arm/
cp docs/arm.yaml.sample arm.yaml
sudo mkdir /etc/arm/
sudo ln -s /opt/arm/arm.yaml /etc/arm/
```

**Set up drives**

  Create mount point for each dvd drive.
  If you don't know the device name try running 'dmesg | grep -i dvd'.  The mountpoint needs to be /mnt/dev/<device name>.
  So if your device name is sr0, set the mountpoint with this command:
  ```bash
  sudo mkdir -p /mnt/dev/sr0
  ```
  Repeat this for each device you plan on using with ARM.

  Create entries in /etc/fstab to allow non-root to mount dvd-roms
  Example (create for each optical drive you plan on using for ARM):
  ```
  /dev/sr0  /mnt/dev/sr0  udf,iso9660  user,noauto,exec,utf8  0  0
  ```

**Configure ARM**

- Edit your "config" file (located at /opt/arm/arm.yaml) to determine what options you'd like to use.  Pay special attention to the 'directory setup' section and make sure the 'arm' user has write access to wherever you define these directories.


- Edit the music config file (located at /home/arm/.abcde.conf)

- To rip Blu-Rays after the MakeMKV trial is up you will need to purchase a license key or while MakeMKV is in BETA you can get a free key (which you will need to update from time to time) here:  https://www.makemkv.com/forum2/viewtopic.php?f=5&t=1053 and create /home/arm/.MakeMKV/settings.conf with the contents:

        app_Key = "insertlicensekeyhere"

- For ARM to identify movie/tv titles register for an API key at OMDb API: http://www.omdbapi.com/apikey.aspx and set the OMDB_API_KEY parameter in the config file.

After setup is complete reboot...
    
    reboot

Optionally if you want something more stable than master you can download the latest release from the releases page.

## Usage

- Insert disc
- Wait for disc to eject
- Repeat

## Troubleshooting

When a disc is inserted, udev rules should launch a script (scripts/arm_wrapper.sh) that will launch ARM.  Here are some basic troubleshooting steps:
- Look for empty.log.  
  - Everytime you eject the cdrom, an entry should be entered in empty.log like:
  ```
  [2018-08-05 11:39:45] INFO ARM: main.<module> Drive appears to be empty or is not ready.  Exiting ARM.
  ```
  - Empty.log should be in your logs directory as defined in your arm.yaml file.  If there is no empty.log file, or entries are not being entered when you eject the cdrom drive, then udev is not launching ARM correctly.  Check the instructions and make sure the symlink to 51-automedia.rules is set up right.  I've you've changed the link or the file contents you need to reload your udev rules with:
  ```
  sudo udevadm control --reload_rules 
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
