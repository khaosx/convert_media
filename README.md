# convert_media.sh

Wrapper script for batch control of video transcoding
v1.24

## Requires:
 
* [Don Melton's video transcoding gem](https://github.com/donmelton/video_transcoding)
* task-spooler - UNIX task scheduler 
  * installed by `brew install task-spooler`
* [slack-cli | Powerful Slack CLI via pure bash](https://github.com/rockymadden/slack-cli) 
  * installed by: 
    * `brew tap rockymadden/rockymadden`
	* `brew install rockymadden/rockymadden/slack-cli`
* [MediaInfo](https://mediaarea.net)
  * installed by: 
    * `brew install media-info`
		
## Notes:

The version number of this script will be tied to Don Melton's gem version (e.g. 1.25 will be script version 1, gem v .25), applicable to anything transcoded with version .20 or lower of Don's project. This is done to allow for quick ID of parameters used for media encoded with that version of the script. 