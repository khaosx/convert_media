#!/bin/bash
###############################################################################
# convert_media.sh                                                            #
#                                                                             #
# Copyright 2019 - K. Austin Newman                                           #
# Convert media using Don Melton's Video Transcoding Project                  #
#                                                                             #
###############################################################################

# -----------------------------------------------------------------
#  Variables go here
# -----------------------------------------------------------------

intVersion=1.25.03

# Make this the root you want everything to happen in
dirWorkVolume="/Volumes/Data/Workflows"

dirProcessing="$dirWorkVolume/Encoding/Processing"
dirArchive="$dirWorkVolume/Outbox/Archive"
strTVRegEx="([sS]([0-9]{2,}|[X]{2,})[eE]([0-9]{2,}|[Y]{2,}))"
dirEncodingLogs="/Volumes/MediaArchive/Encoding Logs"

# -----------------------------------------------------------------
#  Begin Script
# -----------------------------------------------------------------

# Verify that environment is correct, and all directories
if [ ! -d "$dirWorkVolume" ]; then
  echo "$dirWorkVolume is not present. Aborting."
  strExit="True"
fi

for dir in Outbox/Archive Outbox/Exceptions Outbox/Movies Outbox/TV Encoding/Intake Encoding/Ready Encoding/Processing Encoding/Staging/720p Encoding/Staging/4k Encoding/Staging/Default Encoding/Staging/Raw Encoding/Staging/x265
	do
		strTestDir="$dirWorkVolume/$dir"
		test -d "$strTestDir" || { mkdir -p "$strTestDir"; echo "$strTestDir not present. Creating. Script will exit after checks."; strExit="True"; }
	done
	
# Now, let's make sure that we have met all the requirements
for tool in ffprobe ts transcode-video slack; do
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

# Take all command line arguments and pass through to test options
strTestOpts="$*"

if [[ "$strTestOpts" = "prep" ]]; then
	fArray=()
	while IFS=  read -r -d $'\0'; do
    fArray+=("$REPLY")
	done < <(find "$dirWorkVolume/Encoding/Intake" -type f -name "*.mkv" -print0)
	tLen=${#fArray[@]}
	for (( i=0; i < tLen; i++ ));
	do
  		strTheFile="${fArray[$i]}"
  		echo "Processing $strTheFile"
  		
  		# Flag any track labeled "forced" 
  		OLDIFS=$IFS
		IFS=$'\n'
		intSubCount=0
		for subtrack in $(ffprobe -i "$strTheFile" -select_streams s -show_streams -of json -v quiet | jq -r '.streams[] | .tags | .title')
		do
			((intSubCount++))
			if [[ "$subtrack" =~ [Ff][Oo][Rr][Cc][Ee][Dd] ]]; then
				echo Setting forced subtitle track on "$strTheFile" - Subtitle track = "$intSubCount"
				mkvpropedit --edit track:s"$intSubCount" --set flag-forced=1 "$strTheFile" 
			fi
		done
  		IFS=$OLDIFS
  		
  		# Move file to default processing 
  		if [[ "$strTheFile" =~ $strTVRegEx ]]; then
			/usr/local/bin/filebot -rename "$strTheFile" --db TheTVDB --format "$dirWorkVolume/Encoding/Staging/Ready/{n} - {s00e00} - {t}" -non-strict
		else
			/usr/local/bin/filebot -rename "$strTheFile" --db TheMovieDB --format "$dirWorkVolume/Encoding/Staging/Ready/{n.colon(' - ')} ({y})" -non-strict
	 	fi
	 	
	done
exit 0
fi

strGeneralOpts="--crop detect --fallback-crop ffmpeg"

# Create array of all MKV files found in the workflow
fArray=()
while IFS=  read -r -d $'\0'; do
    fArray+=("$REPLY")
done < <(find "$dirWorkVolume/Encoding/Staging" -type f -name "*.mkv" -not -path "*Ready*" -print0)

tLen=${#fArray[@]}
for (( i=0; i < tLen; i++ ));
	do
		strTheFile="${fArray[$i]}"
		echo Processing "$strTheFile"
		strFilename=$(basename "$strTheFile")
		strExtension="${strFilename##*.}"
		strFilename="${strFilename%.*}"
		strFileProfile=$(echo "$strTheFile" | awk -F/ '{print $(NF-1)}')

		# Get media info
		strMI=$(ffprobe -i "$strTheFile" -show_format -show_streams -show_data -print_format json=compact=1 2>/dev/null)
		strMIName=$(echo "$strMI" | jq '.format|.tags|.title')
		intHeight=$(echo "$strMI" | jq '.streams[0]|.height')
		if (( intHeight <= 480 )); then
			strHeight="DVD"
		elif  (( intHeight > 480 )) && (( intHeight <= 720 )); then
			strHeight="720p"
		elif (( intHeight > 720 )) && (( intHeight <= 1080 )); then
			strHeight="1080p"
		elif (( intHeight > 1080 )); then
			strHeight="2160p"
		fi
		
		# Compare file name and movie name. If different, write new movie name.
		if [ "$strFilename" != "$strMIName" ]; then
			mkvpropedit "$strTheFile" --edit info --set "title=$strFilename" >/dev/null 2>&1
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
			strDestLabel="H265 BluRay-$strHeight"
		elif [ "$strFileProfile" = "4k" ]; then
			strVideoOpts="--avbr --quick"
			strDestLabel="BluRay-$strHeight"
		else
			if [ "$strHeight" = "DVD" ]; then
				strVideoOpts="--avbr --quick --target 480p=2000"
				strDestLabel="DVD"
			else
				strDestLabel="BluRay-1080p"
				strVideoOpts="--max-height 1080 --avbr --quick"
			fi
		fi

		strDestFileName="$strFilename $strDestLabel.$strExtension"
		strArchFileName="$strFilename Remux-$strHeight.$strExtension"
		strDestOpts="$dirProcessing/$strDestFileName"

		# Set Subtitle Options - Soft add all eng subtitles, find forced and mark in file
		OLDIFS=$IFS
		IFS=$'\n'
		intSubCount=0
		strSubOpts="--no-auto-burn"
		strSubInfo=$(ffprobe -i "$strTheFile" -select_streams s -show_streams -print_format json=compact=1 2>/dev/null)
  		for subtrack in $(echo "$strSubInfo" | jq -r '.streams[] | .disposition | .forced')
		do
			strLanguage=$(echo "$strSubInfo" | jq -r ".streams[$intSubCount] | .tags | .language")
			((intSubCount++))
			if [[ "$subtrack" = "1" ]] && [ "$strLanguage" = "eng" ]; then
				strSubOpts="$strSubOpts --add-subtitle $intSubCount --force-subtitle $intSubCount"
			elif [ "$strLanguage" = "eng" ]; then
				strSubOpts="$strSubOpts --add-subtitle $intSubCount"
			fi
		done
		
		# Set Audio Options
		declare -a aAudioOptions
		unset aAudioOptions
		intAudCount=0
		strAudioInfo=$(ffprobe -i "$strTheFile" -select_streams a -show_streams -print_format json=compact=1 2>/dev/null)
		for audtrack in $(echo "$strAudioInfo" | jq -r '.streams[] | .tags | .title')
		do
			strLanguage=$(echo "$strAudioInfo" | jq -r ".streams[$intAudCount] | .tags | .language")
			((intAudCount++))
			if [ "$strLanguage" = "eng" ] && [[ "$audtrack" =~ [Cc][Oo][Mm][Mm][Ee][Nn][Tt][Aa][Rr][Yy] ]]; then
				aAudioOptions+=('--add-audio' $intAudCount=$audtrack )
			elif [ "$strLanguage" = "eng" ]; then
				aAudioOptions+=("--add-audio" "$intAudCount" )
			fi
		done
		aAudioOptions+=('--audio-width' '1=surround' '--ac3-encoder' 'eac3' '--ac3-bitrate' '640' '--keep-ac3-stereo')
		IFS=$OLDIFS

		# Here we go. Time to start the process.
		mv "$strTheFile" "$dirProcessing"
		strSourceFile="$dirProcessing/$strFilename.$strExtension"
		if [[ "$strDestFileName" =~ $strTVRegEx ]]; then
			strDestFile="$dirWorkVolume/Outbox/TV/$strDestFileName"
		else
			mkdir -p "$dirWorkVolume/Outbox/Movies/$strFilename"
			strDestFile="$dirWorkVolume/Outbox/Movies/$strFilename/$strDestFileName"
		fi
		ts slack chat send -tx "$strFilename has started transcoding." -ch '#encoding' --filter '.ts' >/dev/null 2>&1
		ts transcode-video $strGeneralOpts $strVideoOpts "${aAudioOptions[@]}" $strSubOpts $strTestOpts --output "$strDestOpts" "$strSourceFile" >/dev/null 2>&1
		ts -d mkvpropedit "$strDestOpts" --edit info --set "muxing-application=vtp_$intVersion" >/dev/null 2>&1
		ts -d mv "$strSourceFile" "$dirArchive/$strArchFileName" >/dev/null 2>&1
		ts -d mv "$strDestOpts" "$strDestFile" >/dev/null 2>&1
		ts -d mv "$strDestOpts.log" "$dirEncodingLogs" >/dev/null 2>&1
		ts -d slack chat send -tx "$strFilename has finished transcoding." -ch '#encoding' --filter  '.ts' >/dev/null 2>&1
	done

echo "No files remain to be processed. Exiting..."
exit 0
