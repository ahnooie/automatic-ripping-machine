#!/bin/bash
# Transcodes Video files using HandBrake and removes source files when done

# shellcheck source=config
# shellcheck disable=SC1091
# shellcheck disable=SC2034
LOG_PREFIX="Transcode_${2}"

# shellcheck disable=SC1090
source "$ARM_CONFIG"

SRC=$1
LABEL=$2
HAS_NICE_TITLE=$3
VIDEO_TYPE=$4
TIMESTAMP=$5

echo "${LOG} START transcode.sh ($LABEL -> $SRC)" | ts >> "$INFO_LOG"

	TRANSSTART=$(date +%s);
	echo "Start video transcoding script" >> "$LOG"

	if [ "$HAS_NICE_TITLE" = true ]; then
		echo "transcoding with a nice title" >> "$LOG"
		DEST="${ARMPATH}/${LABEL}"
		echo "dest ${DEST} variable created"
		if [ -d "$DEST" ]; then
			echo "directory already exists... adding timestamp" >> "$LOG"
			DEST="${ARMPATH}/${LABEL}_${TIMESTAMP}"
		fi
	else
		echo "transcoding without a nice title" >> "$LOG"
		DEST="${ARMPATH}/${LABEL}_${TIMESTAMP}"
	fi	

	# DEST="${ARMPATH}/${LABEL}_${TIMESTAMP}"
	mkdir -p "$DEST"
	if [ "$SKIP_TRANSCODE" = true ] && [ "$RIPMETHOD" = "mkv" ]; then
		# this only works for files ripped by MakeMKV into .mkv files
		echo "Skipping transcode.  Moving files from $SRC to $DEST" >> "$LOG"
		mv "$SRC"/* "$DEST"/  >> "$LOG"
	elif [ "$RIPMETHOD" = "backup" ] && [ "$MAINFEATURE" = true ] && [ "$ID_CDROM_MEDIA_BD" = "1" ]; then
		echo "Transcoding BluRay main feature only." >> "$LOG"
		# shellcheck disable=SC2086
		$HANDBRAKE_CLI -i "$SRC" -o "$DEST/$LABEL.$DEST_EXT" --main-feature --preset="$HB_PRESET" $HB_ARGS 2>> "$LOG"
		rmdir "$SRC"	
	elif [ "$RIPMETHOD" = "backup" ] && [ "$MAINFEATURE" = false ] && [ "$ID_CDROM_MEDIA_BD" = "1" ]; then		
		echo "Transcoding BluRay all titles above minlength." >> "$LOG"
		# Itterate through titles of MakeMKV backup
		# First check if this is the main title
		MAINTITLENO="$(echo ""|HandBrakeCLI --input "$SRC" --title 0 --scan |& grep -B 1 "Main Feature" | sed 's/[^0-9]*//g')"

		# Get number of titles
		TITLES="$(echo ""|HandBrakeCLI --input "$SRC" --scan |& grep -Po '(?<=scan: BD has )([0-9]+)')"
		echo "$TITLES titles on BluRay Disc" >> "$LOG"

		for TITLE in $(seq 1 "$TITLES")
		do
			echo "Processing title $TITLE" >> "$LOG"

			TIME="$(echo ""|HandBrakeCLI --input "$SRC" --title "$TITLE" --scan |& grep 'duration is' | sed -r 's/.*\((.*)ms\)/\1/')"
			
			SEC=$(( TIME / 1000 )) >> "$LOG"
			echo "Title length is $SEC seconds." >> "$LOG"
			if [ $SEC -gt "$MINLENGTH" ]; then
				echo "HandBraking title $TITLE"
				# shellcheck disable=SC2086
				$HANDBRAKE_CLI -i "$SRC" -o "$DEST/$LABEL-$TITLE.$DEST_EXT" --min-duration="$MINLENGTH" -t "$TITLE" --preset="$HB_PRESET" $HB_ARGS 2  >> "$LOG"

				# Check for main title and rename
				if [ "$MAINTITLENO" = "$TITLE" ] && [ "$HAS_NICE_TITLE" = true ]; then
					echo "Sending the following command: mv -n \"$DEST/$LABEL-$TITLE.$DEST_EXT\" \"${DEST}/${LABEL}.${DEST_EXT}\"" >> "$LOG"
					mv -n "$DEST/$LABEL-$TITLE.$DEST_EXT" "${DEST}/${LABEL}.${DEST_EXT}" >> "$LOG"
				fi
			else    
				echo "Title $TITLE lenth less than $MINLENGTH.  Skipping." >> "$LOG"
			fi
		done	
		rm -rf "$SRC"
	elif [ "$MAINFEATURE" = true ] && [ "$ID_CDROM_MEDIA_DVD" = "1" ]; then
		echo "Transcoding DVD main feature only." >> "$LOG"
		# echo "$HANDBRAKE_CLI -i $DEVNAME -o \"${DEST}/${LABEL}.${DEST_EXT}\" --main-feature --preset="${HB_PRESET}" --subtitle scan -F 2" >> $LOG
		# shellcheck disable=SC2086
        $HANDBRAKE_CLI -i "$DEVNAME" -o "${DEST}/${LABEL}.${DEST_EXT}" --main-feature --preset="${HB_PRESET}" $HB_ARGS 2>> "$LOG"
		eject "$DEVNAME"
	else
		echo "Transcoding all files." >> "$LOG"
		# shellcheck disable=SC2045
	        for FILE in $(ls "$SRC")
                	do
                	filename=$(basename "$FILE")

                	#extension=${filename##*.}
                	filename=${filename%.*}

			echo "Transcoding file $FILE" >> "$LOG"
				# shellcheck disable=SC2086
                $HANDBRAKE_CLI -i "$SRC/$FILE" -o "$DEST/$filename.$DEST_EXT" --preset="$HB_PRESET" $HB_ARGS 2>> "$LOG"
			rm "$SRC/$FILE"
       		done
		rmdir "$SRC"
	fi

	embyrefresh ()
	{
			ApiKey="$(curl -s -H "Authorization: MediaBrowser Client=\"$EMBY_CLIENT\", Device=\"$EMBY_DEVICE\", DeviceId=\"$EMBY_DEVICEID\", Version=1.0.0.0, UserId=\"$EMBY_USERID\"" -d "username=$EMBY_USERNAME" -d "password=$EMBY_PASSWORD" "http://$EMBY_SERVER:$EMBY_PORT/users/authenticatebyname?format=json" | python -m json.tool | grep 'AccessToken' | sed 's/\"//g; s/AccessToken://g; s/\,//g; s/ //g')"

			RESPONSE=$(curl -d 'Library' "http://$EMBY_SERVER:$EMBY_PORT/Library/Refresh?api_key=$ApiKey")

			if [ ${#RESPONSE} = 0 ]; then
				# scan was successful
				echo "Emby refresh command sent successfully" >> "$LOG"
			else
				# scan failed
				echo "Emby refresh command failed for some reason.  Probably authentication issues" >> "$LOG"
			fi
	}

	if [ "$VIDEO_TYPE" = "movie" ] && [ "$MAINFEATURE" = true ] && [ "$HAS_NICE_TITLE" = true ] && [ "$EMBY_SUBFOLDERS" = false ]; then
		# move the file to the final media directory
		# shellcheck disable=SC2129,SC2016
		echo '$VIDEO_TYPE is movie, $MAINFEATURE is true, $HAS_NICE_TITLE is true, $EMBY_SUBFOLDERS is false' >> "$LOG"
		echo "Moving a single file." >> "$LOG"
        echo "Checing for existing file..." >> "$LOG"
		if [ ! -f "$MEDIA_DIR/$LABEL.$DEST_EXT" ]; then
			echo "No file found.  Moving \"$DEST/$LABEL.$DEST_EXT to $MEDIA_DIR/$LABEL.$DEST_EXT\"" >> "$LOG"
			mv -n "$DEST/$LABEL.$DEST_EXT" "$MEDIA_DIR/$LABEL.$DEST_EXT"
			
			if [ "$SET_MEDIA_PERMISSIONS" = true ]; then
			
			chmod -R "$CHMOD_VALUE" "$MEDIA_DIR"
							
			fi

			if [ "$EMBY_REFRESH" = true ]; then
				# signal emby to scan library
				embyrefresh
			else
				echo "Emby Refresh False.  Skipping library scan" >> "$LOG"
			fi
		else	
			echo "Warning: $MEDIA_DIR/$LABEL.$DEST_EXT File exists! File moving aborted" >> "$LOG"
        fi
    elif [ "$VIDEO_TYPE" = "movie" ] && [ "$MAINFEATURE" = true ] && [ "$HAS_NICE_TITLE" = true ] && [ "$EMBY_SUBFOLDERS" = true ]; then
		# shellcheck disable=SC2129,SC2016
		echo '$VIDEO_TYPE is movie, $MAINFEATURE is true, $HAS_NICE_TITLE is true, $EMBY_SUBFOLDERS is true' >> "$LOG"
        echo "Moving a single file to emby subfolders" >> "$LOG"
		mkdir -p "$MEDIA_DIR/$LABEL" >> "$LOG"
		if [ ! -f "$MEDIA_DIR/$LABEL/$LABEL.$DEST_EXT" ]; then
			echo "No file found.  Moving \"$DEST/$LABEL.$DEST_EXT to $MEDIA_DIR/$LABEL/$LABEL.$DEST_EXT\"" >> "$LOG"
			mv -n "$DEST/$LABEL.$DEST_EXT" "$MEDIA_DIR/$LABEL/$LABEL.$DEST_EXT"
			
			if [ "$SET_MEDIA_PERMISSIONS" = true ]; then
			
			chmod -R "$CHMOD_VALUE" "$MEDIA_DIR/$LABEL"
						
			fi

			if [ "$EMBY_REFRESH" = true ]; then
				# signal emby to scan library
				embyrefresh
			else
				echo "Emby Refresh False.  Skipping library scan" >> "$LOG"
			fi
		else	
			echo "Warning: $MEDIA_DIR/$LABEL/$LABEL.$DEST_EXT File exists! File moving aborted" >> "$LOG"
        fi
	elif [ "$VIDEO_TYPE" = "movie" ] && [ "$MAINFEATURE" = false ] && [ "$HAS_NICE_TITLE" = true ] && [ "$EMBY_SUBFOLDERS" = false ]; then
		# shellcheck disable=SC2129,SC2016
		echo '$VIDEO_TYPE is movie, $MAINFEATURE is false, $HAS_NICE_TITLE is true, $EMBY_SUBFOLDERS is false' >> "$LOG"
		# hopefully this is never happen because it will cause a lot of duplicate files
		echo "***WARNING!*** This will likely leave files in the transcoding directory as there is very likely existing files in the media directory"
        echo "Moving multiple files to emby movie folder" >> "$LOG"
		mv -n "$DEST/$LABEL.$DEST_EXT" "$MEDIA_DIR/$LABEL.$DEST_EXT"
		
		if [ "$SET_MEDIA_PERMISSIONS" = true ]; then
			
		chmod -R "$CHMOD_VALUE" "$MEDIA_DIR"
					
		fi
		
		if [ "$EMBY_REFRESH" = true ]; then
			# signal emby to scan library
			embyrefresh
		else
			echo "Emby Refresh False.  Skipping library scan" >> "$LOG"
		fi
	elif [ "$VIDEO_TYPE" = "movie" ] && [ "$MAINFEATURE" = false ] && [ "$HAS_NICE_TITLE" = true ] && [ "$EMBY_SUBFOLDERS" = true ]; then
		# shellcheck disable=SC2129,SC2016
		echo '$VIDEO_TYPE is movie, $MAINFEATURE is false, $HAS_NICE_TITLE is true, $EMBY_SUBFOLDERS is true' >> "$LOG"
        echo "Moving multiple files to emby movie subfolders" >> "$LOG"
		echo "First move main title" >> "$LOG"
        mkdir -p -v "$MEDIA_DIR/$LABEL" >> "$LOG"
		if [ ! -f "$MEDIA_DIR/$LABEL/$LABEL.$DEST_EXT" ]; then
			echo "No file found.  Moving \"$DEST/$LABEL.$DEST_EXT to $MEDIA_DIR/$LABEL/$LABEL.$DEST_EXT\"" >> "$LOG"
			mv -n "$DEST/$LABEL.$DEST_EXT" "$MEDIA_DIR/$LABEL/$LABEL.$DEST_EXT" >> "$LOG"
			
			if [ "$SET_MEDIA_PERMISSIONS" = true ]; then
			
			chmod -R "$CHMOD_VALUE" "$MEDIA_DIR/$LABEL"
						
			fi
			
		fi

		#now move "extras"
		if [ "$PLEX_SUPPORT" = true ]; then
		
			# shellcheck disable=SC2129,SC2016
			mkdir -p -v "$MEDIA_DIR/$LABEL/Featurettes" >> "$LOG"
			
			# Create Emby ignore file for "extras" Folder
			touch "$MEDIA_DIR/$LABEL/Featurettes/.ignore"  >> "$LOG"
			
			# shellcheck disable=SC2086
       			echo "Sending command: mv -n "\"$DEST/$LABEL/*\"" "\"$MEDIA_DIR/$LABEL/Featurettes/\""" >> "$LOG"
       			mv -n "${DEST}"/* "$MEDIA_DIR/$LABEL/Featurettes/" >> "$LOG"
			
			# Move Largest file to main folder for Plex/Emby/Kodi to detect main movie
			# shellcheck disable=SC2012
			ls -S "$MEDIA_DIR/$LABEL/Featurettes/" | head -1 | xargs -I '{}' mv "$MEDIA_DIR/$LABEL/Featurettes/"{} "$MEDIA_DIR/$LABEL/$LABEL.mkv" >> "$LOG"
			
			if [ "$SET_MEDIA_PERMISSIONS" = true ]; then
			
			chmod -R "$CHMOD_VALUE" "$MEDIA_DIR/$LABEL"
						
			fi
		else
				
			# shellcheck disable=SC2129,SC2016
			mkdir -p -v "$MEDIA_DIR/$LABEL/extras" >> "$LOG"
				
			# Create Plex ignore file for "extras" Folder
			touch "$MEDIA_DIR/$LABEL/extras/.plexignore"  >> "$LOG"
			
			# shellcheck disable=SC2086
      			echo "Sending command: mv -n "\"$DEST/$LABEL/*\"" "\"$MEDIA_DIR/$LABEL/extras/\""" >> "$LOG"
       			mv -n "${DEST}"/* "$MEDIA_DIR/$LABEL/extras/" >> "$LOG"
			
			# Move Largest file to main folder for Plex/Emby/Kodi to detect main movie
			# shellcheck disable=SC2012
			ls -S "$MEDIA_DIR/$LABEL/extras/" | head -1 | xargs -I '{}' mv "$MEDIA_DIR/$LABEL/extras/"{} "$MEDIA_DIR/$LABEL/$LABEL.mkv" >> "$LOG"
			
			if [ "$SET_MEDIA_PERMISSIONS" = true ]; then
			
			chmod -R "$CHMOD_VALUE" "$MEDIA_DIR/$LABEL"
						
			fi
			
			if [ "$EMBY_REFRESH" = true ]; then
				# signal emby to scan library
					embyrefresh
			else
					echo "Emby Refresh False.  Skipping library scan" >> "$LOG"
			fi
				
		fi
		rmdir "$DEST"
	fi

rmdir "$SRC" 

TRANSEND=$(date +%s);
TRANSSEC=$((TRANSEND-TRANSSTART));
TRANSTIME="$((TRANSSEC / 3600)) hours, $(((TRANSSEC / 60) % 60)) minutes and $((TRANSSEC % 60)) seconds."

echo "STAT: ${ID_FS_LABEL} transcoded in ${TRANSTIME}" >> "$LOG"

#echo /opt/arm/rename.sh $DEST

echo /opt/arm/notify.sh "\"Transcode: ${ID_FS_LABEL} completed in ${TRANSTIME}\"" |at now

echo "${LOG} END transcode.sh ($LABEL -> $SRC)" | ts >> "$INFO_LOG"

