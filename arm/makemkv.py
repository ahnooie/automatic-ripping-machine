#!/usr/bin/python3

import sys
import os
import logging
import subprocess
import time
import shlex

from config import cfg
from getmakemkvcode import grabcode

# If you would like to auto grab a MakeMKV key
# NOTE: this may be provide MakeMKV with a blotched code if you have no internet at the time of ripping.
# TODO: Move this to config i don't know how your config works
autograbcode = True


def makemkv(logfile, disc):
    """
    Rip Blurays with MakeMKV\n
    logfile = Location of logfile to redirect MakeMKV logs to\n
    disc = disc object\n

    Returns path to ripped files.
    """
    if autograbcode is True:
        logging.info("Auto Grabbing MakeMKV Code")
        grabcode()
    logging.info("Starting MakeMKV rip. Method is " + cfg['RIPMETHOD'])

    # get MakeMKV disc number
    logging.debug("Getting MakeMKV disc number")
    cmd = 'makemkvcon -r info disc:9999  |grep {0} |grep -oP \'(?<=:).*?(?=,)\''.format(
                disc.devpath
    )

    try:
        mdisc = subprocess.check_output(
            cmd,
            shell=True
        ).decode("utf-8")
        logging.info("MakeMKV disc number: " + mdisc.strip())
        # print("mdisc is: " + mdisc)
    except subprocess.CalledProcessError as mdisc_error:
        err = "Call to makemkv failed with code: " + str(mdisc_error.returncode) + "(" + str(mdisc_error.output) + ")"
        logging.error(err)
        # print("Error: " + err)
        return

    # get filesystem in order
    rawpath = os.path.join(cfg['RAWPATH'], disc.videotitle)
    logging.info("Destination is " + rawpath)

    if not os.path.exists(rawpath):
        try:
            os.makedirs(rawpath)
        except OSError:
            # logging.error("Couldn't create the base file path: " + rawpath + " Probably a permissions error")
            err = "Couldn't create the base file path: " + rawpath + " Probably a permissions error"
    else:
        logging.info(rawpath + " exists.  Adding timestamp.")
        ts = round(time.time() * 100)
        rawpath = os.path.join(cfg['RAWPATH'], disc.videotitle + "_" + str(ts))
        logging.info("rawpath is " + rawpath)
        try:
            os.makedirs(rawpath)
        except OSError:
            # logging.error("Couldn't create the base file path: " + rawpath + " Probably a permissions error")
            err = "Couldn't create the base file path: " + rawpath + " Probably a permissions error"
            sys.exit(err)

    # rip bluray
    if cfg['RIPMETHOD'] == "backup" and disc.disctype == "bluray":
        cmd = 'makemkvcon backup --decrypt {0} -r disc:{1} {2}>> {3}'.format(
            cfg['MKV_ARGS'],
            mdisc.strip(),
            shlex.quote(rawpath),
            logfile
        )
        logging.info("Backup up disc")
        logging.debug("Backing up with the following command: " + cmd)
    elif cfg['RIPMETHOD'] == "mkv" or disc.disctype == "dvd":
        cmd = 'makemkvcon mkv {0} -r dev:{1} all {2} --minlength={3}>> {4}'.format(
            cfg['MKV_ARGS'],
            disc.devpath,
            shlex.quote(rawpath),
            cfg['MINLENGTH'],
            logfile
        )
        logging.info("Ripping disc")
        logging.debug("Ripping with the following command: " + cmd)
    else:
        logging.info("I'm confused what to do....  Passing on MakeMKV")

    try:
        mkv = subprocess.run(
            cmd,
            shell=True
        )
        # ).decode("utf-8")
        # print("mkv is: " + mkv)
        logging.debug("The exit code for MakeMKV is: " + str(mkv.returncode))
    except subprocess.CalledProcessError as mdisc_error:
        err = "Call to MakeMKV failed with code: " + str(mdisc_error.returncode) + "(" + str(mdisc_error.output) + ")"
        logging.error(err)
        # print("Error: " + mkv)
        return None

    disc.eject()

    logging.info("Exiting MakeMKV processing with return value of: " + rawpath)
    return(rawpath)
