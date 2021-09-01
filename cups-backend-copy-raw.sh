#!/usr/bin/env bash

# Put it into /usr/lib/cups/backend/bbb-copy-raw

# This virtual "printer" is run after BigBlueButton collects
# all artefacts of the meeting to /var/bigbluebutton/recording/raw/$meeting_id
# and sends all that to a special worker which processes (converts) recordings.
# All recordings are sent, even those where recording was not turned on,
# because it may have been not turned on erroneously and so we still have
# to keep the recording artefact. The storage of recordings will rotate them.
# "Printer class" in CUPS may be used to load balance processing of recordings
# to multiple workers. Printer Device URI can be used to show which "printer"
# (recordings processing worker) has been chosen by CUPS.

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
	if [ $? != "$CUPS_BACKEND_FAILED" ]; then
		exit "$CUPS_BACKEND_RETRY"
	fi
}
trap '_trap_exit' EXIT

input=""

case ${#} in
	0 )
		# This is CUPS listing backends
		# device-class scheme "Unknown" "device-info"
		echo direct bbb-copy-raw \"Unknown\" \"Collect raw recording of BigBlueButton\"
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

# Examples of valid URIs:
# - local/srv/container2/raw
#   it means copy from /var/bigbluebutton/recording/raw/$meeting_id to /srv/container2/raw/$meeting_id
DEVICE_URI="$(echo "$DEVICE_URI" | sed -e 's,^bbb-copy-raw://,,' -e 's,^bbb-copy-raw:/,,')"
case "$DEVICE_URI" in
	local/* )
		# https://docstore.mik.ua/orelly/unix3/upt/ch10_13.htm
		# pack /var/bigbluebutton/recording/raw/$meeting_id into file.tar (root of $meeting_id = root of tarball)
		# and send to stdin of CUPS
		target_dir=/"$(echo "$DEVICE_URI" | sed -e 's,^local/,,')"
		if ! test -d "$target_dir"; then
			echo CRIT: directory "$target_dir" does not exist! 1>&2
			exit "$CUPS_BACKEND_FAILED"
		fi
		mkdir -p "$target_dir"/"$jobtitle"
		dd if="$input" | tar -C "$target_dir"/"$jobtitle" xf -
		echo > "$target_dir"/"$jobtitle"/.cups.copied_raw
		chown -R bigbluebutton:bigbluebutton "$target_dir"/"$jobtitle"
		# TODO: rebuild recordings via CUPS instead of bbb worker in ruby
		#if [ "$target_dir" = /var/bigbluebutton/recording/raw ]; then
		#	bbb-record --rebuild "$jobtitle"
		#fi
	;;
# XXX ssh probably makes no sense here, comment it for now
# ssh can make sense if we use ionotify on directory where new recordings appear and run building task
# but we run CUPS on every wndpoint, so ssh seems to not make any sense
#	ssh/* )
#		ssh_port="$(echo "$DEVICE_URI" | awk -F '/' '{print $2}')"
#		ssh_userhost="$(echo "$DEVICE_URI" | awk -F '/' '{print $3}')"
#		# ssh/port/user@host/remote_path/dir1/dir2 -> remote_path/dir1/dir2
#		# https://stackoverflow.com/a/49130247
#		ssh_remote_path="$(echo "$DEVICE_URI" | awk -F '/' '{for(i=4; i<=NF; ++i) printf "%s/", $i;}')"
#		# TODO: run as sudo -u <special user> ssh ...
#		ssh -p "$ssh_port" "$ssh_userhost" mkdir -p "$ssh_remote_path"/"$jobtitle"
#		dd if="$input" | ssh -p "$ssh_port" "$ssh_userhost" tar -C "$ssh_remote_path"/"$jobtitle" xf -
#	;;
	* )
		echo CRIT: Device URI is not supported! 1>&1
		exit "$CUPS_BACKEND_FAILED"
	;;
esac
