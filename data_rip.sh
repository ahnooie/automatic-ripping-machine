#!/bin/bash
# Rip Data using DD

# shellcheck disable=SC1091
# shellcheck source=config
source "$ARM_CONFIG"

{



        TIMESTAMP=$(date '+%Y%m%d_%H%M%S');
        DEST="/mnt/media/ARM/Media/Data/${TIMESTAMP}_${ID_FS_LABEL}"
        mkdir -p "$DEST"
	FILENAME=${ID_FS_LABEL}_disc.iso


	#dd if=/dev/sr0 of=$DEST/$FILENAME 
	cat "$DEVNAME" > "$DEST/$FILENAME"

	eject
	
	chmod 777 -r "$DEST"

} >> "$LOG"
