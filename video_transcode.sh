#!/bin/bash
# Transcodes Video files using HandBrake and removes source files when done

source /opt/arm/config

SRC=$1
LABEL=$2
TIMESTAMP=$3
TRANSSTART=$(date +%s);


echo "Start video transcoding script" >> $LOG

	DEST=${ARMPATH}/${LABEL}_${TIMESTAMP}
	mkdir $DEST

	if [ $RIPMETHOD = "backup" ] && [ "$MAINFEATURE" = true ] && [ $ID_CDROM_MEDIA_BD = "1" ]; then
		echo "Transcoding BluRay main feature only." >> $LOG
		$HANDBRAKE_CLI -i $SRC -o $DEST/$LABEL.$DEST_EXT --main-feature --preset="$HB_PRESET" --subtitle scan -F 2>> $LOG
		rmdir -rf $SRC
	elif [ $RIPMETHOD = "backup" ] && [ "$MAINFEATURE" = false ] && [ $ID_CDROM_MEDIA_BD = "1" ]; then
		echo "Transcoding BluRay all titles above minlength." >> $LOG
		$HANDBRAKE_CLI -i $SRC -o $DEST/$LABEL.$DEST_EXT --min-duration $MINLENGTH --preset="$HB_PRESET" --subtitle scan -F 2>> $LOG
		rmdir -rf $SRC
	elif [ $MAINFEATURE = true ] && [ $ID_CDROM_MEDIA_DVD = "1" ]; then
		echo "Transcoding DVD main feature only." >> $LOG
                $HANDBRAKE_CLI -i $DEVNAME -o $DEST/$LABEL.$DEST_EXT --main-feature --preset="$HB_PRESET" --subtitle scan -F 2>> $LOG
		eject $DEVNAME
		rmdir $SRC
	else
		echo "Transcoding all files." >> $LOG
	        for FILE in `ls $SRC`
                	do
                	filename=$(basename $FILE)
                	extension=${filename##*.}
                	filename=${filename%.*}

			echo "Transcoding file $FILE" >> $LOG

                	$HANDBRAKE_CLI -i $SRC/$FILE -o $DEST/$filename.$DEST_EXT --preset="$HB_PRESET" --subtitle scan -F 2>> $LOG
			rm $SRC/$FILE
       		done
		rmdir $SRC
	fi

#rmdir $SRC

TRANSEND=$(date +%s);
TRANSSEC=$(($TRANSEND-$TRANSSTART));
TRANSTIME="$(($TRANSSEC / 3600)) hours, $((($TRANSSEC / 60) % 60)) minutes and $(($TRANSSEC % 60)) seconds."

echo "STAT: ${ID_FS_LABEL} transcoded in ${TRANSTIME}" >> $LOG

#echo /opt/arm/rename.sh $DEST

echo /opt/arm/notify.sh "\"Transcode: ${ID_FS_LABEL} completed in ${TRANSTIME}\"" |at now

