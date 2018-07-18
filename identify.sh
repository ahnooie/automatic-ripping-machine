#!/bin/bash

export ARM_CONFIG=$1
export DISC_INFO=$2
DEVNAME=$3

mkdir -p /tmp/arm_locks
LOCKDIR=/tmp/arm_locks/$DEVNAME

function cleanup {
    if rmdir $LOCKDIR; then
        echo "Finished"
    else
        echo "Failed to remove lock directory '$LOCKDIR'"
        exit 1
    fi
}

echo "$ARM_CONFIG"

# shellcheck source=config
# shellcheck disable=SC1091
source "$ARM_CONFIG"
# shellcheck disable=SC1090
source "$DISC_INFO"

# Determine logfile name
# If LOG_SINGLE_FILE is set to true, log all activity to ARM.log
# If false (default) use the label of the DVD/CD or else use empty.log
# this is required for udev events where there is no media available
# such as ejecting the drive

if [ "$LOG_SINGLE_FILE" == true ]; then
	LOGFILE="ARM.log"
else
	if [ -n "$ID_FS_LABEL" ]; then
        LOGFILE=${ID_FS_LABEL}".log"
        elif [[ -n "$ID_CDROM_MEDIA_TRACK_COUNT_AUDIO" && $(which abcde-musicbrainz-tool) ]]; then
                LOGFILE=$(abcde-musicbrainz-tool --device "$DEVNAME" | cut -f1 -d ' ')".log"
        elif [[ -n "$ID_CDROM_MEDIA_TRACK_COUNT_AUDIO" &&  $(which cd-discid) ]]; then
                LOGFILE=$(cd-discid "$DEVNAME" | cut -f1 -d ' ')".log"
	else
        LOGFILE="empty.log"
	fi
fi

# Set full logfile path
LOG=$LOGPATH$LOGFILE

# Create log dir if needed
mkdir -p "$LOGPATH"

# mkdir is atomic - only one instance of this script can successfully make the
# directory.n
if mkdir $LOCKDIR
then
    # this ensures that the lockdir is removed whenever this script exits.
    # normally, sigterm, etc. if it exits via SIGKILL, the lockdir will *not* be
    # cleaned up.
    trap "cleanup" EXIT
    echo "Got lock for $DEVNAME" >> $LOG
else
    echo "Exiting early from ripping $DEVNAME because lockdir \"$LOCKDIR\" already exists. If no other process is ripping from $DEVNAME, feel free to \"rmdir $LOCKDIR\" and try again."
    exit 1
fi


#shellcheck disable=SC2094
{
# echo all config parameters to logfile
# excludes sensative parameters
# shellcheck disable=SC2129
echo "*** Start config parameters ****" >> "$LOG"
echo -e "\tTimestamp: $(date -R)" >> "$LOG"
# shellcheck disable=SC2002
cat "$ARM_CONFIG"|sed '/^[#;].*$/d;/^$/d;/if/d;/^ /d;/^else/d;/^fi/d;/KEY=/d;/PASSWORD/d' >> "$LOG"
echo "*** End config parameters ****" >> "$LOG"

echo "Starting Identify Script..." >> "$LOG"

VIDEO_TITLE=""
HAS_NICE_TITLE=""


#Clean up old log files
FILESFOUND=( $(find "$LOGPATH" -mtime +"$LOGLIFE" -type f))
echo "Deleting ${#FILESFOUND[@]} old log files: ${FILESFOUND[*]}" >> "$LOG"
find "$LOGPATH" -mtime +"$LOGLIFE" -type f -delete

# Set Home to home folder of user that is setup to run MakeMKV
export HOME="/root/"

# Output UDEV info
udevadm info -q env -n "$DEVNAME" >> "$LOG"

if [ "$ID_FS_TYPE" == "udf" ]; then
	echo "identified udf" >> "$LOG"
	echo "found ${ID_FS_LABEL} on ${DEVNAME}" >> "$LOG"

	if [ "$ARM_CHECK_UDF" == true ]; then
		# check to see if this is really a video
		mkdir -p /mnt/"$DEVNAME"
		mount "$DEVNAME" /mnt/"$DEVNAME"
		# shellcheck disable=SC2086
		# shellcheck disable=SC2010
		# shellcheck disable=SC2126
		if [[ -d /mnt/${DEVNAME}/VIDEO_TS || -d /mnt/${DEVNAME}/BDMV || -d /mnt/${DEVNAME}/HVDVD_TS || $(ls -laR /mnt/${DEVNAME}/ 2>/dev/null |grep -P "HVDVD_TS" |wc -l) == 1 ]]; then
			echo "identified udf as video" >> "$LOG"

			if [ "$GET_VIDEO_TITLE" == true ]; then

				GET_TITLE_OUTPUT=$(/opt/arm/getmovietitle.py -p /mnt"${DEVNAME}" 2>&1)
				GET_TITLE_RESULT=$?

				if [ $GET_TITLE_RESULT = 0 ]; then
					echo "Obtained Title $GET_TITLE_OUTPUT"
					HAS_NICE_TITLE=true
					VIDEO_TITLE=${GET_TITLE_OUTPUT}
				else
					echo "failed to get title $GET_TITLE_OUTPUT"
					HAS_NICE_TITLE=false
					VIDEO_TITLE=${ID_FS_LABEL}
				fi

			else
				HAS_NICE_TITLE=false
				VIDEO_TITLE=${ID_FS_LABEL}
			fi

			if [ $HAS_NICE_TITLE == true ]; then
				VTYPE=$(/opt/arm/getvideotype.py -t "${VIDEO_TITLE}" -k "${OMDB_API_KEY}" 2>&1)

				#handle year mismath if found
				if [[ $VTYPE =~ .*#.* ]]; then
					VIDEO_TYPE=$(echo "$VTYPE" | cut -f1 -d#)
					NEW_YEAR=$(echo "$VTYPE" | cut -f2 -d#)
					echo "VIDEO_TYPE is $VIDEO_TYPE and NEW_YEAR is $NEW_YEAR"
					VIDEO_TITLE="$(echo "$VIDEO_TITLE" | cut -f1 -d\()($NEW_YEAR)"
					echo "Year mismatch found.  New video title is $VIDEO_TITLE"
				else
					VIDEO_TYPE="$VTYPE"
				fi
			else
				VIDEO_TYPE="unknown"
			fi

			echo "got to here"
			echo "HAS_NICE_TITLE is ${HAS_NICE_TITLE}"
			echo "video title is now ${VIDEO_TITLE}"
			echo "video type is ${VIDEO_TYPE}"

			umount "/mnt/$DEVNAME"
			/opt/arm/video_rip.sh "$VIDEO_TITLE" "$HAS_NICE_TITLE" "$VIDEO_TYPE" "$LOG"
		else
			umount "/mnt/$DEVNAME"
			echo "identified udf as data" >> "$LOG"
			/opt/arm/data_rip.sh "$LOG"
			eject "$DEVNAME"

		fi
	else
		echo "ARM_CHECK_UDF is false, assuming udf is video" >> "$LOG"
		/opt/arm/video_rip.sh "UnknownTitle" "false" "unknown" "$LOG"
	fi


elif [ -n "$ID_CDROM_MEDIA_TRACK_COUNT_AUDIO" ]; then
	echo "identified audio" >> "$LOG"
	abcde -d "$DEVNAME"
    if [ "$NOTIFY_RIP" = "true" ]; then
	    echo /opt/arm/notify.sh "\"Audio Rip: ${ID_FS_LABEL} completed from ${DEVNAME}\" \"$LOG\"" |at -M now
	fi

elif [ "$ID_FS_TYPE" == "iso9660" ]; then
	echo "identified data" >> "$LOG"
	/opt/arm/data_rip.sh "$LOG"
	eject "$DEVNAME"
elif [ -z "${ID_CDROM_MEDIA+x}" ] && [ -z "${ID_FS_TYPE}" ]; then
	echo "drive seems empty, not ejecting" >> "$LOG"
else
	echo "unable to identify"
	echo "$ID_CDROM_MEDIA_TRACK_COUNT_AUDIO" >> "$LOG"
	echo "$ID_FS_TYPE" >> "$LOG"
	eject "$DEVNAME"
fi

rm "$DISC_INFO"

} >> "$LOG"
