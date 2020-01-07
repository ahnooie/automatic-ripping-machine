#!/usr/bin/python3

import os
import sys
import logging
import fcntl
import subprocess
import shutil
import requests

from config import cfg


def notify(title, body):
    # Send notificaions
    # title = title for notification
    # body = body of the notification

    if cfg['PB_KEY'] != "":
        try:
            from pushbullet import Pushbullet
            pb = Pushbullet(cfg['PB_KEY'])
            pb.push_note(title, body)
        except:  # noqa: E722
            logging.error("Failed sending PushBullet notification.  Continueing processing...")

    if cfg['IFTTT_KEY'] != "":
        try:
            import pyfttt as pyfttt
            event = cfg['IFTTT_EVENT']
            pyfttt.send_event(cfg['IFTTT_KEY'], event, title, body)
        except:  # noqa: E722
            logging.error("Failed sending IFTTT notification.  Continueing processing...")

    if cfg['PO_USER_KEY'] != "":
        try:
            from pushover import init, Client
            init(cfg['PO_APP_KEY'])
            Client(cfg['PO_USER_KEY']).send_message(body, title=title)
        except:  # noqa: E722
            logging.error("Failed sending PushOver notification.  Continueing processing...")


def scan_emby():
    """Trigger a media scan on Emby"""

    if cfg['EMBY_REFRESH']:
        logging.info("Sending Emby library scan request")
        url = "http://" + cfg['EMBY_SERVER'] + ":" + cfg['EMBY_PORT'] + "/Library/Refresh?api_key=" + cfg['EMBY_API_KEY']
        try:
            req = requests.post(url)
            if req.status_code > 299:
                req.raise_for_status()
            logging.info("Emby Library Scan request successful")
        except requests.exceptions.HTTPError:
            logging.error("Emby Library Scan request failed with status code: " + str(req.status_code))
    else:
        logging.info("EMBY_REFRESH config parameter is false.  Skipping emby scan.")


def move_files(basepath, filename, hasnicetitle, videotitle, ismainfeature=False):
    """Move files into final media directory
    basepath = path to source directory
    filename = name of file to be moved
    hasnicetitle = hasnicetitle value
    ismainfeature = True/False"""

    logging.debug("Arguments: " + basepath + " : " + filename + " : " + str(hasnicetitle) + " : " + videotitle + " : " + str(ismainfeature))

    if hasnicetitle:
        m_path = os.path.join(cfg['MEDIA_DIR'] + videotitle)

        if not os.path.exists(m_path):
            logging.info("Creating base title directory: " + m_path)
            os.makedirs(m_path)

        if ismainfeature is True:
            logging.info("Track is the Main Title.  Moving '" + filename + "' to " + m_path)

            m_file = os.path.join(m_path, videotitle + "." + cfg['DEST_EXT'])
            if not os.path.isfile(m_file):
                try:
                    shutil.move(os.path.join(basepath, filename), m_file)
                except shutil.Error:
                    logging.error("Unable to move '" + filename + "' to " + m_path)
            else:
                logging.info("File: " + m_file + " already exists.  Not moving.")
        else:
            e_path = os.path.join(m_path, cfg['EXTRAS_SUB'])

            if not os.path.exists(e_path):
                logging.info("Creating extras directory " + e_path)
                os.makedirs(e_path)

            logging.info("Moving '" + filename + "' to " + e_path)

            e_file = os.path.join(e_path, videotitle + "." + cfg['DEST_EXT'])
            if not os.path.isfile(e_file):
                try:
                    shutil.move(os.path.join(basepath, filename), os.path.join(e_path, filename))
                except shutil.Error:
                    logging.error("Unable to move '" + filename + "' to " + e_path)
            else:
                logging.info("File: " + e_file + " already exists.  Not moving.")

    else:
        logging.info("hasnicetitle is false.  Not moving files.")


def make_dir(path):
    """
Make a directory\n
    path = Path to directory\n

    returns success True if successful
        false if the directory already exists
    """
    if not os.path.exists(path):
        logging.debug("Creating directory: " + path)
        try:
            os.makedirs(path)
            return True
        except OSError:
            err = "Couldn't create a directory at path: " + path + " Probably a permissions error.  Exiting"
            logging.error(err)
            sys.exit(err)
            # return False
    else:
        return False


def get_cdrom_status(devpath):
    """get the status of the cdrom drive\n
    devpath = path to cdrom\n

    returns int
    CDS_NO_INFO		0\n
    CDS_NO_DISC		1\n
    CDS_TRAY_OPEN		2\n
    CDS_DRIVE_NOT_READY	3\n
    CDS_DISC_OK		4\n

    see linux/cdrom.h for specifics\n
    """

    try:
        fd = os.open(devpath, os.O_RDONLY | os.O_NONBLOCK)
    except Exception:
        logging.info("Failed to open device " + devpath + " to check status.")
        exit(2)
    result = fcntl.ioctl(fd, 0x5326, 0)

    return result


def find_file(filename, search_path):
    """
    Check to see if file exists by searching a directory recursively\n
    filename = filename to look for\n
    search_path = path to search recursively\n

    returns True or False
    """

    for dirpath, dirnames, filenames in os.walk(search_path):
        if filename in filenames:
            return True
    return False


def rip_music(disc, logfile):
    """
    Rip music CD using abcde using abcde config\n
    disc = disc object\n
    logfile = location of logfile\n

    returns True/False for success/fail
    """

    if disc.disctype == "music":
        logging.info("Disc identified as music")
        cmd = 'abcde -d "{0}" >> "{1}" 2>&1'.format(
            disc.devpath,
            logfile
        )

        logging.debug("Sending command: " + cmd)

        try:
            subprocess.check_output(
                cmd,
                shell=True
            ).decode("utf-8")
            logging.info("abcde call successful")
            return True
        except subprocess.CalledProcessError as ab_error:
            err = "Call to abcde failed with code: " + str(ab_error.returncode) + "(" + str(ab_error.output) + ")"
            logging.error(err)
            # sys.exit(err)

    return False


def rip_data(disc, datapath, logfile):
    """
    Rip data disc using cat on the command line\n
    disc = disc object\n
    datapath = path to copy data to\n
    logfile = location of logfile\n

    returns True/False for success/fail
    """

    if disc.disctype == "data":
        logging.info("Disc identified as data")

        if (disc.label) == "":
            disc.label = "datadisc"

        incomplete_filename = os.path.join(datapath, disc.label + ".part")
        final_filename = os.path.join(datapath, disc.label + ".iso")

        logging.info("Ripping data disc to: " + incomplete_filename)

        cmd = 'cat "{0}" > "{1}" 2>> {2}'.format(
            disc.devpath,
            incomplete_filename,
            logfile
        )

        logging.debug("Sending command: " + cmd)

        try:
            subprocess.check_output(
                cmd,
                shell=True
            ).decode("utf-8")
            logging.info("Data rip call successful")
            os.rename(incomplete_filename, final_filename)
            return True
        except subprocess.CalledProcessError as dd_error:
            err = "Data rip failed with code: " + str(dd_error.returncode) + "(" + str(dd_error.output) + ")"
            logging.error(err)
            os.unlink(incomplete_filename)

    return False


def set_permissions(directory_to_traverse):
    try:
        corrected_chmod_value = int(str(cfg['CHMOD_VALUE']), 8)
        logging.info("Setting permissions to: " + str(cfg['CHMOD_VALUE']) + " on: " + directory_to_traverse)
        os.chmod(directory_to_traverse, corrected_chmod_value)

        for dirpath, l_directories, l_files in os.walk(directory_to_traverse):
            for cur_dir in l_directories:
                logging.debug("Setting path: " + cur_dir + " to permissions value: " + str(cfg['CHMOD_VALUE']))
                os.chmod(os.path.join(dirpath, cur_dir), corrected_chmod_value)
            for cur_file in l_files:
                logging.debug("Setting file: " + cur_file + " to permissions value: " + str(cfg['CHMOD_VALUE']))
                os.chmod(os.path.join(dirpath, cur_file), corrected_chmod_value)
        return True
    except Exception as e:
        err = "Permissions setting failed as: " + str(e)
        logging.error(err)
        return False
