#!/usr/bin/env bash

# Put it into /usr/lib/cups/backend/bbb-build-recording

# Authors:
# - Mikhail Novosyolov <mikhailnov@dumalogiya.ru>, 2021

# Based on examples at https://community.kde.org/Printing/Developer_Tools
# Docs:
# - backend(7) https://www.cups.org/doc/man-backend.html
###############################################################################

set -efu
set -o pipefail

# jobtitle=meeting ID (/var/bigbluebutton/recording/raw/$meeting_id),
# we are not interested in all other variables
readonly jobtitle=${3}

BBB_DIR_RAW="${BBB_DIR_RAW:-/var/bigbluebutton/recording/raw}"

# Exit codes from /usr/include/cups/backend.h
CUPS_BACKEND_OK=0                  # Job completed successfully
CUPS_BACKEND_FAILED=1              # Job failed, use error-policy
CUPS_BACKEND_AUTH_REQUIRED=2       # Job failed, authentication required
CUPS_BACKEND_HOLD=3                # Job failed, hold job
CUPS_BACKEND_STOP=4                # Job failed, stop queue
CUPS_BACKEND_CANCEL=5              # Job failed, cancel job
CUPS_BACKEND_RETRY=6               # Job failed, retry this job later
CUPS_BACKEND_RETRY_CURRENT=7       # Job failed, retry this job immediately

# We use 'set -e', script may fail somewhere,
# make CUPS restart the job later if the error was unexpected
_trap_exit(){
	if [ $? != "$CUPS_BACKEND_OK" ] && [ $? != "$CUPS_BACKEND_FAILED" ]; then
		exit "$CUPS_BACKEND_RETRY"
	fi
}
trap '_trap_exit' EXIT

input=""

case ${#} in
	0 )
		# This is CUPS listing backends
		# device-class scheme "Unknown" "device-info"
		echo direct bbb-build-recording \"Unknown\" \"Build recording of BigBlueButton\"
		exit
	;;
	12 )
		input=/dev/stdin
	;;
	13 )
		# do not remove {} here!
		input="${13}"
	;;
	* )
		echo CRIT: unsupported number of arguements! 1>&2
		exit "$CUPS_BACKEND_FAILED"
	;;
esac

if [ "$jobtitle" = "(stdin)" ]; then
	echo CRIT: printing job must be titled! 1>&2
	exit "$CUPS_BACKEND_FAILED"
fi

if [ -z "$jobtitle" ]; then
	echo CRIT: empty title of the printing job! 1>&2
	exit "$CUPS_BACKEND_FAILED"
fi

if ! test -d "$BBB_DIR_RAW"/"$jobtitle" ; then
	echo CRIT: recording ${jobtitle} does not exist! 1>&2
	exit "$CUPS_BACKEND_FAILED"
fi

if ! test -f "$BBB_RAW_DIR"/"$jobtitle"/events.xml ; then
	echo CRIT: recording ${jobtitle} does not have events.xml! 1>&2
	exit "$CUPS_BACKEND_FAILED"
fi

# TODO: process it by ourself
# TODO: watch *.failed and *.done files
# TODO: use ionotify
c=0
while true
do
	# 2 hours
	if [ $c -gt 240 ]; then
		echo CRIT: timeout waiting for BBB to process recording ${jobtitle} 1>&2
		exit "$CUPS_BACKEND_RETRY"
	fi
	if test -f /var/bigbluebutton/recording/status/processed/${jobtitle}-presentation.fail; then
		echo CRIT: BBB failed to process recording ${jobtitle} 1>&2
		exit "$CUPS_BACKEND_FAILED"
	fi
	if test -f /var/bigbluebutton/recording/status/processed/${jobtitle}-presentation.done ; then
		echo INFO: BBB has processed recording ${jobtitle} 1>&2
		exit "$CUPS_BACKEND_OK"
	fi
	sleep 30s
	c=$((++c))
done
