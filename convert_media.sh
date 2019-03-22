#!/bin/bash

# Make this the root you want everything to happen in
dirWorkVolume="/Volumes/Data/Workflows"

# Verify that environment is correct, and all directories
if [ ! -d "$dirWorkVolume" ]; then
  echo "$dirWorkVolume is not present. Aborting."
  exit 1
fi

for dir in Outbox/Archive Outbox/Exceptions Outbox/Movies Outbox/TV Encoding/Intake/Movies Encoding/Intake/TV Encoding/Processing Encoding/Staging/720p Encoding/Staging/4k Encoding/Staging/Default Encoding/Staging/Raw Encoding/Staging/x265
	do
		strTestDir="$dirWorkVolume/$dir"
		test -d "$strTestDir" || { mkdir -p "$strTestDir"; echo "$strTestDir not present. Creating. Script will exit after checks."; strExit="True"; }
	done
	
# Now, let's make sure that we have met all the requirements
for tool in mediainfo ts transcode-video slack; do
    command -v $tool >/dev/null 2>&1 || { echo "Executable not in \$PATH: $tool" >&2; strExit="True"; }
done

if [ "$strExit" = "True" ]; then
	exit 1
fi

# Clean out the task spooler queue, if handbrake not running, kill taskspooler
if ! pgrep -f "HandBrakeCLI" >/dev/null 2>&1 ; then
    ts -K
fi
ts -C

# Set variables
dirProcessing="$dirWorkVolume/Encoding/Processing"
dirExceptions="$dirWorkVolume/Outbox/Exceptions"
dirArchive="$dirWorkVolume/Outbox/Archive"
strTVRegEx="([sS]([0-9]{2,}|[X]{2,})[eE]([0-9]{2,}|[Y]{2,}))"
dirEncodingLogs="/Volumes/Media/Encoding Logs"

# Take all command line arguments and pass through to test options
strTestOpts="$*"

if [[ "$strTestOpts" = "prep" ]]; then
	files=/Volumes/Data/Workflows/Encoding/Intake/*.mkv
	for file in $files
	do
  		echo "Processing $file"
  		if [[ "$file" =~ $strTVRegEx ]]; then
			/usr/local/bin/filebot -rename "$file" --db TheTVDB --format "/Volumes/Data/Workflows/Encoding/Staging/Default/{n} - {s00e00} - {t}" -non-strict
		else
			/usr/local/bin/filebot -rename "$file" --db TheMovieDB --format "/Volumes/Data/Workflows/Encoding/Staging/Default/{n.colon(' - ')} ({y})" -non-strict
	 	fi
	done
exit 0
fi

if [[ "$strTestOpts" == "*log*" ]]; then
	strGeneralOpts="--crop detect --fallback-crop minimal"
else
	strGeneralOpts="--crop detect --fallback-crop minimal"
fi

# Create array of all MKV files found in the workflow
OLDIFS=$IFS
IFS=$'\n'
fArray=($(find "$dirWorkVolume/Encoding/Staging" -type f -name "*.mkv" ))
IFS=$OLDIFS
tLen=${#fArray[@]}
for (( i=0; i < tLen; i++ ));
	do
		strTheFile="${fArray[$i]}"
		strFilename=$(basename "$strTheFile")
		strExtension="${strFilename##*.}"
		strFilename="${strFilename%.*}"
		strFileProfile=$(echo "$strTheFile" | awk -F/ '{print $(NF-1)}')

		# Get media info
		strMI=$(mediainfo --Output=file://"$HOME"/scripts/convert_media_mi.template "$strTheFile")
		strMIName=$(echo "$strMI" | cut -f1 -d '^')
		strMIApp=$(echo "$strMI" | cut -f2 -d '^')
		intNumVideoStream=$(echo "$strMI" | cut -f3 -d '^')
		intNumAudioStream=$(echo "$strMI" | cut -f4 -d '^')
		intSubCount=$(echo "$strMI" | cut -f5 -d '^')
		intHeight=$(echo "$strMI" | cut -f6 -d '^')
		if (( intHeight <= 480 )); then
			strHeight="DVD"
		elif  (( intHeight > 480 )) && (( intHeight <= 720 )); then
			strHeight="720p"
		elif (( intHeight > 720 )) && (( intHeight <= 1080 )); then
			strHeight="1080p"
		elif (( intHeight > 1080 )); then
			strHeight="2160p"
		fi

		# Basic checks to make sure we have a semi-decent source

		# Determine if raw or transcoded. Move to exceptions if transcoded.
		if [[ $strMIApp =~ "HandBrake" ]]; then
			echo "$strFilename is not original source. Moving to exception folder."
			mv "$strTheFile" "$dirExceptions/"
			continue
		fi

		if [ -z "$intNumVideoStream" ]; then
			echo "$strFilename is invalid - no video stream. Moved to exception folder."
			mv "$strTheFile" "$dirExceptions/"
			continue
		fi 
		
		if [ -z "$intNumAudioStream" ]; then
			echo "$strFilename is invalid - no audio stream. Moved to exception folder."
			mv "$strTheFile" "$dirExceptions/"
			continue
		fi 
		
		# If we're still going, then it's ok to proceed

		# Compare file name and movie name. If different, write new movie name.
		if [ "$strFilename" != "$strMIName" ]; then
			mkvpropedit "$strTheFile" --edit info --set "title=$strFilename"
		fi

		# Find out what kind of transcode we're dealing with. 
		# Raw - No encoding, renames original to spec, copies to archive and outbox
		# 720p constrains height to 720 pixels, encodes file with x264, renames original, copies to archive and outbox 
		# x265 will use 10-bit x265 encoder, encodes file, renames original, copies to archive and outbox
		# 4k encodes file w x264, renames original, copies to archive and outbox
		# Default constrains height to 1080p, encodes file with x264, renames original, copies to archive and outbox
		 
		if [ "$strFileProfile" = "Raw" ]; then
			strArchFileName="$strFilename Remux-$strHeight.$strExtension"
			cp -c "$strTheFile" "$dirArchive/$strArchFileName"
			mv "$strTheFile" "$dirWorkVolume/Workflows/Outbox/$strArchFileName"
			continue
		elif [ "$strFileProfile" = "720p" ]; then
			strDestLabel="BluRay-720p"
			strVideoOpts="--720p --avbr --quick"
		elif [ "$strFileProfile" = "x265" ]; then
			strVideoOpts="--abr --handbrake-option encoder=x265_10bit"
			strDestLabel="BluRay-$strHeight H265"
		elif [ "$strFileProfile" = "4k" ]; then
			strVideoOpts="--avbr --quick"
			strDestLabel="BluRay-$strHeight"
		else
			if [ "$strHeight" = "DVD" ]; then
				strVideoOpts="--avbr --quick --target 480p=2000"
				strDestLabel = "DVD"
			else
				strDestLabel="BluRay-1080p"
				strVideoOpts="--max-height 1080 --avbr --quick"
			fi
		fi

		strDestFileName="$strFilename $strDestLabel.$strExtension"
		strArchFileName="$strFilename Remux-$strHeight.$strExtension"
		strDestOpts="$dirProcessing/$strDestFileName"

		# Set Subtitle Options - Soft add all eng subtitles, find forced and mark in file
		if (( intSubCount > 0 )); then
				strSubOpts="--add-subtitle eng --no-auto-burn --force-subtitle scan"
		fi
		
		# Set Audio Options
		strAudioOpts="--add-audio eng --audio-width 1=surround --ac3-encoder eac3 --ac3-bitrate 384"

		# Here we go. Time to start the process.
		mv "$strTheFile" "$dirProcessing"
		strSourceFile="$dirProcessing/$strFilename.$strExtension"
		if [[ "$strDestFileName" =~ $strTVRegEx ]]; then
			strDestFile="$dirWorkVolume/Outbox/TV/$strDestFileName"
		else
			mkdir -p "$dirWorkVolume/Outbox/Movies/$strFilename"
			strDestFile="$dirWorkVolume/Outbox/Movies/$strFilename/$strDestFileName"
		fi
		ts slack chat send -tx "$strFilename has started transcoding." -ch '#encoding' --filter  '.ts'
		ts transcode-video $strGeneralOpts $strVideoOpts $strAudioOpts $strSubOpts $strTestOpts --output "$strDestOpts" "$strSourceFile"
		ts -d mv "$strSourceFile" "$dirArchive/$strArchFileName"
		ts -d mv "$strDestOpts" "$strDestFile"
		ts -d mkvpropedit "$strDestFile" --edit info --set "muxing-application=vtp_1.25.1"
		if [ -z "$strTestOpts" ]; then
			ts -d mv "$strDestOpts.log" "$dirEncodingLogs"
		fi
		ts -d slack chat send -tx "$strFilename has finished transcoding." -ch '#encoding' --filter  '.ts'

	done
exit 0
