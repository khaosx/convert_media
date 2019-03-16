#convert_media.sh

v1.20

Wrapper script for batch control of video transcoding 

##Requires:
 
 	* Don Melton's video transcoding gem 
 		- _https://github.com/donmelton/video_transcoding_ 
 	* task-spooler - UNIX task scheduler 
 		- installed by 'brew install task-spooler 
 	* slack-cli | Powerful Slack CLI via pure bash 
 		_https://github.com/rockymadden/slack-cli_ 
 		- installed by: 
		-'brew tap rockymadden/rockymadden' 
		-_'brew install rockymadden/rockymadden/slack-cli'_ 
		
The version number of this script will be tied to Don Melton's gem version (e.g. 1.25 will be script version 1, gem v .25), applicable to anything transcoded with version .20 or lower of Don's project. This is done to allow for quick ID of parameters used for media encoded with that version of the script. 