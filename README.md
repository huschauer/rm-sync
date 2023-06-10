# rM sync

Sync script for the reMarkable paper tablet.

This script will give you sync and backup functionality over USB. Great if you do not want to sync your rM to the cloud.

_contributions welcome_

## Usage

This script is written for and tested on linux. Feel free to adopt for mac or win.

 1. Create a reMarkable folder somewhere in your documents folder
 2. Save the script file to the reMarkable folder
 3. Change the RMDIR variable (and others) in the file as needed.
 4. Run with `./rm-sync.sh`
 
### Options

 * `u` upload: Uploads new files to the reMarkable (root folder) from local folder _Upload_. After successful upload the files will be deleted in the local folder.
 * `b` backup: Creates a backup of all user files on the reMarkable. The backup is saved to a folder with todays date inside the _Backup_ folder.
 * `d` download: Recreates the folderstructure on your reMarkable inside the _Files_ folder and downloads all files in PDF format.
 * `v` verbose: more detailed output and logging
 
 default setting is `bdu`

## Open issues

 * Error messages regarding not deleting files.index and folders.index

## Prerequisite

 * Passwordless SSH needs to be implemented between your PC and your reMarkable
 * USB web interface needs to activated (Settings -> Storage -> USB web interface)
