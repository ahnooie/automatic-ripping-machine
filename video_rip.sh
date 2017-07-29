#!/bin/bash
# Rip video using MakeMKV then eject and call transcode script

# shellcheck source=config
# shellcheck disable=SC1091
source "$ARM_CONFIG"

echo "${LOG} BEGIN video_rip" | ts >> "$INFO_LOG"

VIDEO_TITLE=$1
HAS_NICE_TITLE=$2
VIDEO_TYPE=$3

{

	echo "Video Title is ${VIDEO_TITLE}"
 	echo "Ripping video ${ID_FS_LABEL} from ${DEVNAME}" >> "$LOG"
	TIMESTAMP=$(date '+%Y%m%d_%H%M%S');
	DEST="${RAWPATH}/${VIDEO_TITLE}_${TIMESTAMP}"
	RIPSTART=$(date +%s);
	mkdir -p "$DEST"

	#echo /opt/arm/video_transcode.sh \"$DEST\" \"$VIDEO_TITLE\" $TIMESTAMP >> $LOG
	if [ "$RIPMETHOD" = "backup" ] && [ "$ID_CDROM_MEDIA_BD" = "1" ]; then
		echo "Using backup method of ripping." >> "$LOG"
		DISC="${DEVNAME: -1}"
		# shellcheck disable=SC2086
		makemkvcon backup --decrypt $MKV_ARGS -r disc:"$DISC" "$DEST"/
		# Note: Don't eject here. the calling script should eject
		echo eject "$DEVNAME"
	elif [ "$MAINFEATURE" = true ] && [ "$ID_CDROM_MEDIA_DVD" = "1" ] && [ -z "$ID_CDROM_MEDIA_BD" ]; then
		echo "Media is DVD and Main Feature parameter in config file is true.  Bypassing MakeMKV." >> "$LOG"
		# rmdir "$DEST"

	echo "DEST is ${DEST}"
	else
		echo "Using mkv method of ripping." >> "$LOG"
		echo "${LOG} MAKING_MOVIE: ${DEST} @ ${DEVNAME}" | ts >> "$INFO_LOG"

        # Disable because MKV_ARGS may be multiple arguments
        # shellcheck disable=SC2086
		makemkvcon mkv $MKV_ARGS dev:"$DEVNAME" all "$DEST" --minlength="$MINLENGTH" -r >> "${LOG}"
		# Note: Don't eject here. the calling script should eject
		echo eject "$DEVNAME"
	fi

	RIPEND=$(date +%s);
	RIPSEC=$((RIPEND-RIPSTART));
	RIPTIME="$((RIPSEC / 3600)) hours, $(((RIPSEC / 60) % 60)) minutes and $((RIPSEC % 60)) seconds."

	#echo /opt/arm/notify.sh "\"Ripped: ${ID_FS_LABEL} completed from ${DEVNAME} in ${RIPTIME}\"" |at now

	echo "STAT: ${ID_FS_LABEL} ripped in ${RIPTIME}" >> "$LOG"

	echo "/opt/arm/video_transcode.sh \"$DEST\" \"$VIDEO_TITLE\" \"$HAS_NICE_TITLE\" \"$VIDEO_TYPE\" $TIMESTAMP"
	echo "/opt/arm/video_transcode.sh \"$DEST\" \"$VIDEO_TITLE\" \"$HAS_NICE_TITLE\" \"$VIDEO_TYPE\" \"$TIMESTAMP\"" | batch

	echo "${ID_FS_LABEL} sent to transcoding queue..." >> "$LOG"

    echo "${LOG} END video_rip" | ts >> "$INFO_LOG"


} >> "$LOG"
