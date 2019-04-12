# convert_media.sh

Wrapper script written in BASH for batch control of video transcoding

v1.25.03

## Requires:
 
* [Don Melton's video transcoding gem](https://github.com/donmelton/video_transcoding)
* task-spooler - UNIX task scheduler 
  * installed by `brew install task-spooler`
* [slack-cli | Powerful Slack CLI via pure bash](https://github.com/rockymadden/slack-cli) 
  * installed by: 
    * `brew tap rockymadden/rockymadden`
	* `brew install rockymadden/rockymadden/slack-cli`
		
## Notes:

The version number of this script will be tied to Don Melton's gem version (e.g. 1.25.1 will be script version 1, gem v .25, minor version 1), applicable to anything transcoded with version .25 or lower of Don's project. This is done to allow for quick ID of parameters used for media encoded with that version of the script. 
