#!/bin/bash
DEVNAME=$1
udevadm info --query=env "/dev/$DEVNAME" > /tmp/arm_disc_info_"$DEVNAME"
echo bash /opt/arm/identify.sh /opt/arm/config /tmp/arm_disc_info_"$DEVNAME" "$DEVNAME" | at -M now
