#!/usr/bin/python3

import sys
sys.path.append("/opt/arm")

import argparse  # noqa: E402
import os  # noqa: E402
import logging  # noqa: E402
import time  # noqa: E402
import datetime  # noqa: E402
import re  # noqa: E402
import shutil  # noqa: E402
import pyudev  # noqa: E402
import getpass  # noqa E402
import psutil  # noqa E402

from arm.ripper import logger, utils, makemkv, handbrake, identify  # noqa: E402
from arm.config.config import cfg  # noqa: E402

from arm.ripper.getkeys import grabkeys  # noqa: E402
from arm.models.models import Job, Config  # noqa: E402
from arm.ui import app, db # noqa E402


def entry():
    """ Entry to program, parses arguments"""
    parser = argparse.ArgumentParser(description='Process disc using ARM')
    parser.add_argument('-d', '--devpath', help='Devpath', required=True)
    parser.add_argument('-t', '--disctype', help='udev disctype', required=False)
    parser.add_argument('-l', '--label', help='udev label', required=False)

    return parser.parse_args()


def log_udev_params():
    """log all udev paramaters"""

    logging.debug("**** Logging udev attributes ****")
    # logging.info("**** Start udev attributes ****")
    context = pyudev.Context()
    device = pyudev.Devices.from_device_file(context, '/dev/sr0')
    for key, value in device.items():
        logging.debug(key + ":" + value)
    logging.debug("**** End udev attributes ****")


def log_arm_params(job):
    """log all entry parameters"""

    # log arm parameters
    logging.info("**** Logging ARM variables ****")
    logging.info("devpath: " + str(job.devpath))
    logging.info("mountpoint: " + str(job.mountpoint))
    logging.info("title: " + str(job.title))
    logging.info("year: " + str(job.year))
    logging.info("video_type: " + str(job.video_type))
    logging.info("hasnicetitle: " + str(job.hasnicetitle))
    logging.info("label: " + str(job.label))
    logging.info("disctype: " + str(job.disctype))
    logging.info("**** End of ARM variables ****")
    logging.info("**** Logging config parameters ****")
    logging.info("skip_transcode: " + str(job.config.SKIP_TRANSCODE))
    logging.info("mainfeature: " + str(job.config.MAINFEATURE))
    logging.info("minlength: " + job.config.MINLENGTH)
    logging.info("maxlength: " + job.config.MAXLENGTH)
    logging.info("videotype: " + job.config.VIDEOTYPE)
    logging.info("manual_wait: " + str(job.config.MANUAL_WAIT))
    logging.info("wait_time: " + str(job.config.MANUAL_WAIT_TIME))
    logging.info("ripmethod: " + job.config.RIPMETHOD)
    logging.info("mkv_args: " + job.config.MKV_ARGS)
    logging.info("delrawfile: " + str(job.config.DELRAWFILES))
    logging.info("hb_preset_dvd: " + job.config.HB_PRESET_DVD)
    logging.info("hb_preset_bd: " + job.config.HB_PRESET_BD)
    logging.info("hb_args_dvd: " + job.config.HB_ARGS_DVD)
    logging.info("hb_args_bd: " + job.config.HB_ARGS_BD)
    logging.info("logfile: " + logfile)
    logging.info("armpath: " + job.config.ARMPATH)
    logging.info("rawpath: " + job.config.RAWPATH)
    logging.info("media_dir: " + job.config.MEDIA_DIR)
    logging.info("extras_sub: " + job.config.EXTRAS_SUB)
    logging.info("emby_refresh: " + str(job.config.EMBY_REFRESH))
    logging.info("emby_server: " + job.config.EMBY_SERVER)
    logging.info("emby_port: " + job.config.EMBY_PORT)
    logging.info("notify_rip: " + str(job.config.NOTIFY_RIP))
    logging.info("notify_transcode " + str(job.config.NOTIFY_TRANSCODE))
    logging.info("max_concurrent_transcodes " + str(job.config.MAX_CONCURRENT_TRANSCODES))
    logging.info("**** End of config parameters ****")


def check_fstab():
    logging.info("Checking for fstab entry.")
    with open('/etc/fstab', 'r') as f:
        lines = f.readlines()
        for line in lines:
            if re.search(job.devpath, line):
                logging.info("fstab entry is: " + line.rstrip())
                return
    logging.error("No fstab entry found.  ARM will likely fail.")


def main(logfile, job):

    """main dvd processing function"""
    logging.info("Starting Disc identification")

    identify.identify(job, logfile)

    if job.disctype in ["dvd", "bluray"]:
        utils.notify(job, "ARM notification", "Found disc: " + str(job.title) + ". Video type is "
                     + str(job.video_type) + ". Main Feature is " + str(job.config.MAINFEATURE)
                     + ".  Edit entry here: http://" + str(job.config.WEBSERVER_IP) + ":" + str(job.config.WEBSERVER_PORT) + "/jobdetail?job_id=" + str(job.job_id))
                     #+ ".  Edit entry here: http://" + job.config.WEBSERVER_IP + ":" + str(job.config.WEBSERVER_PORT))
    elif job.disctype == "music":
        #Fixed bug next line
        utils.notify(job, "ARM notification", "Found music CD: " + str(job.label) + ". Ripping all tracks")
    elif job.disctype == "data":
        utils.notify(job, "ARM notification", "Found data disc.  Copying data.")
    else:
        utils.notify(job, "ARM Notification", "Could not identify disc.  Exiting.")
        sys.exit()

    if job.config.MANUAL_WAIT:
        logging.info("Waiting " + str(job.config.MANUAL_WAIT_TIME) + " seconds for manual override.")
        job.status = "waiting"
        db.session.commit()
        time.sleep(job.config.MANUAL_WAIT_TIME)
        db.session.refresh(job)
        db.session.refresh(config)
        job.status = "active"
        db.session.commit()

    if job.title_manual:
        logging.info("Manual override found.  Overriding auto identification values.")
        job.updated = True
        job.hasnicetitle = True
    else:
        logging.info("No manual override found.")

    log_arm_params(job)

    check_fstab()

    if job.config.HASHEDKEYS:
        logging.info("Getting MakeMKV hashed keys for UHD rips")
        grabkeys()

    if job.disctype in ["dvd", "bluray"]:
        # get filesystem in order
        hboutpath = os.path.join(job.config.ARMPATH, str(job.title))

        if (utils.make_dir(hboutpath)) is False:
            ts = round(time.time() * 100)
            hboutpath = os.path.join(job.config.ARMPATH, str(job.title) + "_" + str(ts))
            if(utils.make_dir(hboutpath)) is False:
                logging.info("Failed to create base directory.  Exiting ARM.")
                sys.exit()

        logging.info("Processing files to: " + hboutpath)

        # Do the work!
        hbinpath = str(job.devpath)
        if job.disctype == "bluray" or (not job.config.MAINFEATURE and job.config.RIPMETHOD == "mkv"):
            # send to makemkv for ripping
            # run MakeMKV and get path to ouput
            job.status = "ripping"
            db.session.commit()
            try:
                mkvoutpath = makemkv.makemkv(logfile, job)
            except:  # noqa: E772
                raise

            if mkvoutpath is None:
                logging.error("MakeMKV did not complete successfully.  Exiting ARM!")
                sys.exit()
            if job.config.NOTIFY_RIP:
                # Fixed bug line below
                utils.notify(job, "ARM notification", str(job.title) + " rip complete.  Starting transcode.")
            # point HB to the path MakeMKV ripped to
            hbinpath = mkvoutpath

            if job.config.SKIP_TRANSCODE and job.config.RIPMETHOD == "mkv":
                logging.info("SKIP_TRANSCODE is true.  Moving raw mkv files.")
                logging.info("NOTE: Identified main feature may not be actual main feature")
                files = os.listdir(mkvoutpath)
                final_directory = hboutpath
                if job.video_type == "movie":
                    logging.debug("Videotype: " + job.video_type)
                    # if videotype is movie, then move biggest title to media_dir
                    # move the rest of the files to the extras folder

                    # find largest filesize
                    logging.debug("Finding largest file")
                    largest_file_name = ""
                    for f in files:
                        # initialize largest_file_name
                        if largest_file_name == "":
                            largest_file_name = f
                        temp_path_f = os.path.join(hbinpath, f)
                        temp_path_largest = os.path.join(hbinpath, largest_file_name)
                        # os.path.join(cfg['MEDIA_DIR'] + videotitle)
                        # if cur file size > largest_file size
                        if(os.stat(temp_path_f).st_size > os.stat(temp_path_largest).st_size):
                            largest_file_name = f
                    # largest_file should be largest file
                    logging.debug("Largest file is: " + largest_file_name)
                    temp_path = os.path.join(hbinpath, largest_file_name)
                    if(os.stat(temp_path).st_size > 0):  # sanity check for filesize
                        for f in files:
                            # move main into media_dir
                            # move others into extras folder
                            if(f == largest_file_name):
                                # largest movie
                                # Encorporating Rajlaud's fix #349
                                utils.move_files(hbinpath, f, job, True)
                            else:
                                # other extras
                                if not str(job.config.EXTRAS_SUB).lower() == "none":
                                    utils.move_files(hbinpath, f, job, False)
                                else:
                                    logging.info("Not moving extra: " + f)
                    # Change final path (used to set permissions)
                    final_directory = os.path.join(job.config.MEDIA_DIR, job.title + " (" + str(job.year) + ")")
                    # Clean up
                    logging.debug("Attempting to remove extra folder in ARMPATH: " + hboutpath)
                    try:
                        shutil.rmtree(hboutpath)
                        logging.debug("Removed sucessfully: " + hboutpath)
                    except Exception:
                        logging.debug("Failed to remove: " + hboutpath)
                else:
                    # if videotype is not movie, then move everything
                    # into 'Unidentified' folder
                    logging.debug("Videotype: " + job.video_type)

                    for f in files:
                        mkvoutfile = os.path.join(mkvoutpath, f)
                        logging.debug("Moving file: " + mkvoutfile + " to: " + mkvoutpath + f)
                        shutil.move(mkvoutfile, hboutpath)
                # remove raw files, if specified in config
                if job.config.DELRAWFILES:
                    logging.info("Removing raw files")
                    shutil.rmtree(mkvoutpath)
                # set file to default permissions '777'
                if job.config.SET_MEDIA_PERMISSIONS:
                    perm_result = utils.set_permissions(job, final_directory)
                    logging.info("Permissions set successfully: " + str(perm_result))
                utils.notify(job, "ARM notification", str(job.title) + " processing complete.")
                logging.info("ARM processing complete")
                # exit
                sys.exit()

        job.status = "transcoding"
        db.session.commit()
        if job.disctype == "bluray" and job.config.RIPMETHOD == "mkv":
            handbrake.handbrake_mkv(hbinpath, hboutpath, logfile, job)
        elif job.disctype == "dvd" and (not job.config.MAINFEATURE and job.config.RIPMETHOD == "mkv"):
            handbrake.handbrake_mkv(hbinpath, hboutpath, logfile, job)
        elif job.video_type == "movie" and job.config.MAINFEATURE and job.hasnicetitle:
            handbrake.handbrake_mainfeature(hbinpath, hboutpath, logfile, job)
            job.eject()
        else:
            handbrake.handbrake_all(hbinpath, hboutpath, logfile, job)
            job.eject()

        # get rid of this
        # if not titles_in_out:
        #     pass

        # check if there is a new title and change all filenames
        # time.sleep(60)
        db.session.refresh(job)
        logging.debug("New Title is " + str(job.title_manual))
        if job.title_manual and not job.updated:
            newpath = utils.rename_files(hboutpath, job)
            p = newpath
        else:
            p = hboutpath

        # move to media directory
        if job.video_type == "movie" and job.hasnicetitle:
            # tracks = job.tracks.all()
            tracks = job.tracks.filter_by(ripped=True)
            for track in tracks:
                logging.info("Moving Movie " + str(track.filename) + " to " + str(p))
                utils.move_files(p, track.filename, job, track.main_feature)


        # move to media directory
        elif job.video_type == "series" and job.hasnicetitle:
            # tracks = job.tracks.all()
            tracks = job.tracks.filter_by(ripped=True)
            for track in tracks:
                logging.info("Moving Series " + str(track.filename) + " to " + str(p))
                utils.move_files(p, track.filename, job, False)
        else:
            logging.info("job type is " + str(job.video_type) + "not movie or series, not moving.")
            utils.scan_emby(job)

        # remove empty directories
        try:
            os.rmdir(hboutpath)
        except OSError:
            logging.info(hboutpath + " directory is not empty.  Skipping removal.")
            pass

        try:
            newpath
        except NameError:
            logging.debug("'newpath' directory not found")
        else:
            logging.info("Found path " + newpath + ".  Attempting to remove it.")
            try:
                os.rmdir(p)
            except OSError:
                logging.info(newpath + " directory is not empty.  Skipping removal.")
                pass

        # Clean up bluray backup
        # if job.disctype == "bluray" and cfg["DELRAWFILES"]:
        if job.config.DELRAWFILES:
            try:
                shutil.rmtree(mkvoutpath)
            except UnboundLocalError:
                logging.debug("No raw files found to delete.")
            except OSError:
                logging.debug("No raw files found to delete.")

        # report errors if any
        if job.errors:
            errlist = ', '.join(job.errors)
            if job.config.NOTIFY_TRANSCODE:
                utils.notify(job, "ARM notification", str(job.title) + " processing completed with errors. Title(s) " + errlist + " failed to complete.")
            logging.info("Transcoding completed with errors.  Title(s) " + str(errlist) + " failed to complete.")
        else:
            if job.config.NOTIFY_TRANSCODE:
                utils.notify(job, "ARM notification", str(job.title) + " processing complete.")
            logging.info("ARM processing complete")

    elif job.disctype == "music":
        if utils.rip_music(job, logfile):
            utils.notify(job, "ARM notification", "Music CD: " + str(job.label) + " processing complete.")
            utils.scan_emby(job)
        else:
            logging.info("Music rip failed.  See previous errors.  Exiting.")

    elif job.disctype == "data":
        # get filesystem in order
        datapath = os.path.join(job.config.ARMPATH, str(job.label))
        if (utils.make_dir(datapath)) is False:
            ts = str(round(time.time() * 100))
            datapath = os.path.join(job.config.ARMPATH, str(job.label) + "_" + ts)

            if(utils.make_dir(datapath)) is False:
                logging.info("Could not create data directory: " + str(datapath) + ".  Exiting ARM.")
                sys.exit()

        if utils.rip_data(job, datapath, logfile):
            utils.notify(job, "ARM notification", "Data disc: " + str(job.label)+ " copying complete.")
            job.eject()
        else:
            logging.info("Data rip failed.  See previous errors.  Exiting.")
            job.eject()

    else:
        logging.info("Couldn't identify the disc type. Exiting without any action.")

    # job.status = "success"
    # job.stop_time = datetime.datetime.now()
    # joblength = job.stop_time - job.start_time
    # minutes, seconds = divmod(joblength.seconds + joblength.days * 86400, 60)
    # hours, minutes = divmod(minutes, 60)
    # len = '{:d}:{:02d}:{:02d}'.format(hours, minutes, seconds)
    # job.job_length = len
    # db.session.commit()


if __name__ == "__main__":
    args = entry()

    devpath = "/dev/" + args.devpath
    print(devpath)

    job = Job(devpath)

    # override disctype from commandline (required in Docker, no udev)
    udev = {}
    if args.disctype:
        (k, v) = args.disctype.split('=', 1)
        udev[k] = v
    if args.label:
        (k, v) = args.label.split('=', 1)
        udev[k] = v
    if args.disctype or args.label:
        job.set_disctype(udev.items())

    logfile = logger.setuplogging(job)
    print("Log: " + logfile)

    if utils.get_cdrom_status(devpath) != 4:
        logging.info("Drive appears to be empty or is not ready.  Exiting ARM.")
        sys.exit()

    logging.info("Starting ARM processing at " + str(datetime.datetime.now()))

    utils.check_db_version(cfg['INSTALLPATH'], cfg['DBFILE'])

    # put in db
    job.status = "active"
    job.start_time = datetime.datetime.now()
    db.session.add(job)
    db.session.commit()
    config = Config(cfg, job_id=job.job_id)
    db.session.add(config)
    db.session.commit()

    # Log version number
    with open(os.path.join(job.config.INSTALLPATH, 'VERSION')) as version_file:
        version = version_file.read().strip()
    logging.info("ARM version: " + version)
    job.arm_version = version
    logging.info(("Python version: " + sys.version).replace('\n', ""))
    logging.info("User is: " + getpass.getuser())

    logger.cleanuplogs(job.config.LOGPATH, job.config.LOGLIFE)

    logging.info("Job: " + str(job.label))

    # a_jobs = Job.query.filter_by(status="active")
    a_jobs = db.session.query(Job).filter(Job.status.notin_(['fail', 'success'])).all()

    # Clean up abandoned jobs
    for j in a_jobs:
        if psutil.pid_exists(j.pid):
            p = psutil.Process(j.pid)
            if j.pid_hash == hash(p):
                logging.info("Job #" + str(j.job_id) + " with PID " + str(j.pid) + " is currently running.")
        else:
            logging.info("Job #" + str(j.job_id) + " with PID " + str(j.pid) + " has been abandoned.  Updating job status to fail.")
            j.status = "fail"
            db.session.commit()

    log_udev_params()

    try:
        main(logfile, job)
    except Exception:
        logging.exception("A fatal error has occured and ARM is exiting.  See traceback below for details.")
        utils.notify(job, "ARM notification", "ARM encountered a fatal error processing " + str(job.title) + ". Check the logs for more details")
        job.status = "fail"
        job.eject()
        # job.stop_time = datetime.datetime.now()
        # job.job_length = job.stop_time - job.start_time
        # job.errors = "ARM encountered a fatal error processing " + str(job.title) + ". Check the logs for more details"
        # # db.session.add(job)
        # db.session.commit()
    else:
        job.status = "success"
    finally:
        job.stop_time = datetime.datetime.now()
        joblength = job.stop_time - job.start_time
        minutes, seconds = divmod(joblength.seconds + joblength.days * 86400, 60)
        hours, minutes = divmod(minutes, 60)
        len = '{:d}:{:02d}:{:02d}'.format(hours, minutes, seconds)
        job.job_length = len
        db.session.commit()
