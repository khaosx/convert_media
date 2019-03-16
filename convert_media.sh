#!/bin/bash

###############################################################################
# convert_media.sh    v1.20                                                   #
#                                                                             #
# Wrapper script for batch control of video transcoding                       #
# Requires:                                                                   #
# 	* Don Melton's video transcoding gem                                      #
# 		https://github.com/donmelton/video_transcoding                        #
# 	* task-spooler - UNIX task scheduler                                      #
# 		installed by 'brew install task-spooler                               #
# 	* slack-cli | Powerful Slack CLI via pure bash                            #
# 		https://github.com/rockymadden/slack-cli                              #
#       installed by:                                                         #
#          'brew tap rockymadden/rockymadden'                                 #
#          'brew install rockymadden/rockymadden/slack-cli                    #
#                                                                             #
# The version number of this script will be tied to Don Melton's gem version  #
# e.g. 1.25 will be script version 1, gem v .25, applicable to anything       #
# transcoded with version .20 or lower of Don's project.                      #
# This is done to allow for quick ID of parameters used for media encoded     #
# with that version of the script.                                            #
#                                                                             #
###############################################################################

# Make this the root volume you want everything to happen on
dirWorkVolume="/Volumes/Data"

# Other necessary locations
movies_local="/Volumes/Data/Workflows/Outbox/Movies"
movies_nas="/Volumes/Media/Movies"

# Set your tools up here
mediainfo=/usr/local/bin/mediainfo
taskspooler=/usr/local/bin/ts
transcoder=/usr/local/bin/transcode-video
slackcli=/usr/local/bin/slack
rsync_exclude_lists="/Users/kris/scripts/rsync excludes"

# Let's prep the environment, just in case
if [ ! -d "$dirWorkVolume" ]; then
  echo "$dirWorkVolume is not present. Aborting."
  exit
fi

for dir in Exceptions Holding Processing
	do
		test -d "$dirWorkVolume/Workflows/Transcode/$dir" || mkdir -p "$dirWorkVolume/Workflows/Transcode/$dir"
 	done

for dir in Movies TV
	do
		for subdir in 720p 1080p_Quick FullHD x265 DVD
			do
				test -d "$dirWorkVolume/Workflows/Transcode/$dir/$subdir" || mkdir -p "$dirWorkVolume/Workflows/Transcode/$dir/$subdir"
			done
	done

for dir in "Copy to Archive Drive" "Move to 4k Drive" Movies TV
	do
		test -d "$dirWorkVolume/Workflows/Outbox/$dir" || mkdir -p "$dirWorkVolume/Workflows/Outbox/$dir"
 	done

# Clean out the task spooler queue, for great justice
if ! pgrep -f "HandBrakeCLI" >/dev/null 2>&1 ; then
    ts -K
fi
ts -C

# Now, let's make sure that we have met all the requirements
for tool in $mediainfo $taskspooler $transcoder $slackcli; do
    if ! $(which $tool >/dev/null); then
        echo "Executable not in \$PATH: $tool" >&2
        exit -1
    fi
done

# Set variables
dirProcessing="$dirWorkVolume/Workflows/Transcode/Processing"
dirExceptions="$dirWorkVolume/Workflows/Transcode/Exceptions"
dirArchive="$dirWorkVolume/Workflows/Outbox/Copy to Archive Drive"
strGeneralOpts="--no-log"
strTestOpts="--chapters 1"
strDonTesting=""

function slack_send {
	$slack chat send -tx "$1" -ch '#media' --filter  '.ts'
}
# Create array of all MKV files found in the workflow
OLDIFS=$IFS
IFS=$'\n'
fArray=($(find "$dirWorkVolume/Workflows/Transcode" -type f -name *.mkv ! -path "$dirWorkVolume/Workflows/Transcode/Holding/*" ! -path "$dirWorkVolume/Workflows/Transcode/Exceptions/*" ! -path "$dirWorkVolume/Workflows/Transcode/Processing/*"))
IFS=$OLDIFS
tLen=${#fArray[@]}
for (( i=0; i<${tLen}; i++ ));
	do
		strTheFile="${fArray[$i]}"
		strFilename=$(basename "$strTheFile")
		strExtension="${strFilename##*.}"
		strFilename="${strFilename%.*}"
		strFileProfile=$(echo "$strTheFile" | awk -F/ '{print $(NF-1)}')
		strFileType=$(echo "$strTheFile" | awk -F/ '{print $(NF-2)}')

		# Get media info
		strMI=$($mediainfo --Output=file://$HOME/scripts/convert_media_mi.template "$strTheFile")
		strMIName=$(echo $strMI | cut -f1 -d \^)
		strMIApp=$(echo $strMI | cut -f2 -d \^)
		intNumVideoStream=$(echo $strMI | cut -f3 -d \^)
		intNumAudioStream=$(echo $strMI | cut -f4 -d \^)
		strSubCount=$(echo $strMI | cut -f5 -d \^)
		intNumChannels=$(echo $strMI | cut -f7 -d \^)
		strCompression=$(echo $strMI | cut -f8 -d \^)
		intHeight=$(echo $strMI | cut -f6 -d \^)

		if [ $intHeight -le 480 ]; then
			strHeight="DVD"
		elif [ $intHeight -gt 480 -a $intHeight -lt 720 ]; then
			strHeight="720p"
		elif [ $intHeight -gt 720 ]; then
			strHeight="1080p"
		fi

		# Basic checks to make sure we have a semi-decent source

		# Determine if raw or transcoded. Move to exceptions if transcoded.
		if [[ $strMIApp =~ "HandBrake" ]]; then
			echo "$strFilename is not original source. Aborting."
			mv "$strTheFile" "$dirExceptions/"
			continue
		fi

		# Has this already been transcoded?
		#if [[ -n $(find /Volumes/Media/Movies/ -type f -name "*$strFilename*") ]];	then
			#echo "$strFilename has already been processed. Aborting."
   			#mv "$strTheFile" "$dirExceptions/"
			#continue
		#fi

		# Is there video?
		if [ -z $intNumVideoStream ]; then
			echo "$strFilename is invalid. No video stream. Moved to exceptions folder"
			mv "$strTheFile" "$dirExceptions/"
			continue
		fi

		# Is there audio?
		if [ -z $intNumAudioStream ]; then
			echo "$strFilename is invalid. No audio stream. Moved to exceptions folder"
			mv "$strTheFile" "$dirExceptions/"
			continue
		fi

		# If we're still going, then it's ok to proceed

		# Carpet should match the drapes and movie name should match file name.
		if [ "$strFilename" != "$strMIName" ]; then
			mkvpropedit "$strTheFile" --edit info --set "title=$strFilename"
		fi

		# Find out what kind of transcode we're dealing with. FullHD receives no transcode and minimal
		# processing. 720p and 1080p get some naming options. DVD also gets none
		if [ $strFileProfile = "FullHD" ]; then
			strArchFileName="$strFilename Remux-1080p.$strExtension"
			cp "$strTheFile" "$dirArchive/$strArchFileName"
			mv "$strTheFile" "$dirWorkVolume/Workflows/Outbox/$strFileType/$strArchFileName"
			continue
		elif [ $strFileProfile = "DVD" ]; then
			strArchFileName="$strFilename DVD.$strExtension"
			cp "$strTheFile" "$dirArchive/$strArchFileName"
			mv "$strTheFile" "$dirWorkVolume/Workflows/Outbox/$strFileType/$strArchFileName"
			continue
		elif [ $strFileProfile = "720p" ]; then
			strDestLabel="BluRay-720p"
		else
			strDestLabel="BluRay-1080p"
		fi

		# Set video options
		strVideoOpts="--avbr --quick --crop detect --fallback-crop ffmpeg"
		if [ $strFileProfile = "720p" ]; then
			strVideoOpts="$strVideoOpts --720p"
		fi
		if [ $strFileProfile = "x265" ]; then
			strVideoOpts="$strVideoOpts --abr --handbrake-option encoder=x265_10bit"
			strDestLabel="$strDestLabel H265"
		fi

		strDestFileName="$strFilename $strDestLabel.$strExtension"
		strArchFileName="$strFilename Remux-$strHeight.$strExtension"

		strDestOpts="$dirProcessing/$strDestFileName"

		# Set Subtitle Options
		if [ ! -f "$dirWorkVolume/Workflows/Transcode/Holding/$strFilename.srt" ]; then
			if [ $strSubCount -eq 1 ]; then
				strSubOpts="--add-subtitle all --no-auto-burn"
			elif [ $strSubCount -eq 2 ]; then
				strSubOpts="--add-subtitle all --no-auto-burn --force-subtitle scan"
			elif [ $strSubCount -gt 2 ]; then
				strSubOpts="--add-subtitle eng --no-auto-burn --force-subtitle scan"
			fi
		fi

		# Set Audio Options
		#if [ "$strCompression" = "Lossless" ]; then
		if [ $strFileProfile = "1080p_FullAudio" ]; then
			strAudioOpts="--copy-audio 1 --audio-width all=double"
		elif [ $intNumChannels -eq 1 ]; then
			strAudioOpts="--add-audio 1 --keep-ac3-stereo"
		elif [ $intNumChannels -eq 2 ]; then
			strAudioOpts="--add-audio 1 --audio-width all=stereo --keep-ac3-stereo"
		elif [ $intNumChannels -gt 2 ]; then
			#strAudioOpts="--add-audio 1 --audio-width 1=double"
			strAudioOpts="--add-audio 1 --audio-width 1=surround"
			#strAudioOpts="--add-audio 1 --audio-width 1=surround --ac3-encoder eac3 --ac3-bitrate 384"
		fi

		# Here we go. Time to start the process.
		mv "$strTheFile" "$dirProcessing"
		strSourceFile="$dirProcessing/$strFilename.$strExtension"
		strDestFile="$dirWorkVolume/Workflows/Outbox/$strFileType/$strDestFileName"
		$taskspooler $slackcli chat send -tx "$strFilename has started transcoding." -ch '#transcodes' --filter  '.ts'
		if [ ! -f "$dirWorkVolume/Workflows/Transcode/Holding/$strFilename.srt" ]; then
			$taskspooler $transcoder $strTestOpts $strDonTesting $strGeneralOpts $strVideoOpts $strAudioOpts $strSubOpts --output "$strDestOpts" "$strSourceFile"
		else
			$taskspooler $transcoder $strTestOpts $strDonTesting $strGeneralOpts $strVideoOpts $strAudioOpts --add-srt "$dirWorkVolume/Workflows/Transcode/Holding/$strFilename.srt" --bind-srt-language eng --no-auto-burn --output "$strDestOpts" "$strSourceFile"
			$taskspooler rm -f "$dirWorkVolume/Workflows/Transcode/Holding/$strFilename.srt"
		fi
		$taskspooler -d mv "$strSourceFile" "$dirArchive/$strArchFileName"
		$taskspooler -d mv "$strDestOpts" "$strDestFile"
		$taskspooler -d $slackcli chat send -tx "$strFilename has finished transcoding." -ch '#transcodes' --filter  '.ts'

	done
exit
