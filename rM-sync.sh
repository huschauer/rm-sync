#!/bin/bash

# Sync script for the reMarkable2 reader
# Version: 0.3
# for backup, download, and upload
# =================
# based on the sync scritp by author: Simon Schilling
# Licence: MIT
# Revised by: Horst Huschauer

# Remote configuration
RMDIR="/home/root/.local/share/remarkable/xochitl/"
RMUSER="root"
RMIP="10.11.99.1"
SSHPORT="22"

# Local configuration
MAINDIR="$HOME/Nextcloud/Documents/reMarkable"
BACKUPDIR="$MAINDIR/Backup/"							# backups by date of all rM contents
UPLOADDIR="$MAINDIR/Upload/"							# all files here will be sent to rM
OUTPUTDIR="$MAINDIR/Files/"								# PDFs of everything on the rM in correct folder structure
OUTPUTDIRBAK="$MAINDIR/Files.bak/"				# Backup of PDFs folder
LOG="sync.log"              							# Log file name in $MAINDIR
BACKUPLIST="files.json"
LOG="$MAINDIR/$(date +%y%m%d)-$LOG"

# Capture the start time
start_time=$(date +%s.%N)

# load arguments
# arguments understood are:
# help -> show help
# v -> very detailed output + logging
# just add the letters of options 
ARG="$1"
if [[ $ARG == "help" ]]; then
	echo "This is the sync script for reMarkable"
	echo "Usage:"
	echo "rm-sync [options]"
	echo "options are"
	echo "help shows this text"
	echo "combine any other options (single letters as below) in one 'word'"
	echo "b -> backup (to Backup folder)"
	echo "d -> download (to Files folder)"
	echo "u -> upload (from Upload folder), file will be deleted from there afterwards"
	echo "v -> very detailed output and logging"
	echo "if no option is provided, 'bdu' will be applied as default"
	echo
	echo "Attention:"
	echo "For down- and uplaods, you need to go to Settings -> Storage"
	echo "and turn USB web interface on!"
	exit 0
fi
if [[ -z $ARG || $ARG == "v" ]]; then
	ARG="bdu$ARG"
fi

# Create array for folders
declare -A folders_array

###################
# Functions:
# ==========

# Function for notification()
notification() {
	notify-send -t 4000 -i "dialog-information" "rm-sync" "$1 $2"
}

# Recursive function to build the full path for each folder
build_full_path() {
    local current_id=$1
    local folder_info=${folders_array["$current_id"]}
    local folder_name=${folder_info% *}
    local parent_id=${folder_info#* }

    if [ "$parent_id" != "0" ]; then
        # Recursively call the function to build the full path
        local parent_folder=$(build_full_path "$parent_id")
        echo "$parent_folder/$folder_name"
    else
        # Reached the root folder
        echo "$folder_name"
    fi
}

# function for removing beginning and ending double quotes and trailing comma
remove_quotes_and_comma() {
	local output="$1"
	output="${output%,}"		# remove trailing comma
	output="${output#\"}"		# remove beginning double quotes
  output=${output// /_}		# new: remove white space characters
	echo "${output%\"}"			# Remove the trailing double quotes
}

# ================
# End of functions
###################

# Create MAINDIR if it does not exist
mkdir -p $MAINDIR
echo $'\n' >> $LOG
date >> $LOG

# check for rM connection
S="ssh -p $SSHPORT -l $RMUSER";
$S $RMIP -q exit

if [ $? == "0" ]; then
	# rM is connected
	# set date -> TODAY
	TODAY=$(date +%y%m%d)

	if [[ $ARG == *"b"* ]]; then
		# Backup of all content on reMarkable
		echo "BEGIN BACKUP" | tee -a $LOG
		# create backup folder if not existing
		mkdir -p "$BACKUPDIR$TODAY"
		# log backup command
		echo "scp -r \"$RMUSER@$RMIP:$RMDIR*\" $BACKUPDIR$TODAY"  >> $LOG
		# execute backup
		scp -r "$RMUSER@$RMIP:$RMDIR*" "$BACKUPDIR$TODAY" >> $LOG 2>&1
		# check for error
		if [ $? -ne 0 ]; then
		  # error
		  ERRORREASON=$ERRORREASON$'\n scp command failed'
		  ERROR=1
		fi
		# Create list of files in backup
	  echo "[" > "$BACKUPDIR$TODAY$BACKUPLIST"
	  find "$BACKUPDIR$TODAY" -name *.metadata -type f -exec sed -s '$a,' {} + | sed '$d' >> "$BACKUPDIR$TODAY$BACKUPLIST"
	  echo "]" >> "$BACKUPDIR$TODAY$BACKUPLIST"
		# log backup completed
		echo "BACKUP END" | tee -a $LOG
	fi
	
	if [[ $ARG == *"d"* ]]; then
		# Download files
		echo "BEGIN DOWNLOAD" | tee -a $LOG
		# copy existing content in download folder to backup folder
		# and create new download folder
		if [[ -e $OUTPUTDIR ]]; then
			echo "copying existing data from folder:" | tee -a $LOG
			echo "$OUTPUTDIR" | tee -a $LOG
			echo "to" | tee -a $LOG
			echo "$OUTPUTDIRBAK" | tee -a $LOG
			mv "$OUTPUTDIR" "$OUTPUTDIRBAK" | tee -a $LOG
		fi
		echo "creating new folder $OUTPUTDIR" | tee -a $LOG 
		mkdir -p "$OUTPUTDIR"
		# create index of all IDs
		ls -1 "$BACKUPDIR$TODAY" | sed -e 's/\..*//g' | awk '!a[$0]++' > "$OUTPUTDIR/index"
		# create an index.json file from all the .metadata files
		echo "[" > "$OUTPUTDIR/index.json";
		for file in "$BACKUPDIR$TODAY"/*.metadata;
		do
		  [ -e "$file" ] || continue
		  echo "{" >> "$OUTPUTDIR/index.json";
		  echo "    \"id\": \"$(basename "$file" .metadata)\"," >> "$OUTPUTDIR/index.json";
		  tail --lines=+2 "$file" >> "$OUTPUTDIR/index.json";
		  echo "," >> "$OUTPUTDIR/index.json";
		done
		truncate -s-2 "$OUTPUTDIR/index.json"; #Remove last comma
		echo "]" >> "$OUTPUTDIR/index.json";
		# done with index.json files
		
		echo "Downloading" $(wc -l < "$OUTPUTDIR/index") "items." | tee -a $LOG
		# Now create folder structure for downloading files
		# Read the folder structure from "type": "CollectionType" and save in file folders.index
		cd "$OUTPUTDIR"
		# create Trash folder
		mkdir -p "Trash"
		echo "trash Trash 0" > folders.index      # create folders.index with trash as first entry
		while read -r line
		do
			# line = iteration of IDs
			# echo "Reading ID $line"
			metadataFile="$BACKUPDIR$TODAY/$line.metadata"
		  idType=$(remove_quotes_and_comma $(grep "\"type\": " "$metadataFile" | awk '{print $2}') )
		  visName=$(remove_quotes_and_comma $(grep "\"visibleName\": " "$metadataFile" | awk '{print $2}') )
		  parent=$(remove_quotes_and_comma $(grep "\"parent\": " "$metadataFile" | awk '{print $2}') )
		  # echo "type: $idType, visibleName: $visName, parent: $parent."
		  if [ "$idType" == "CollectionType" ]; then
		 	  # this line is a folder
		 	  if [ -z "$parent" ]; then
		 	  	parent="0"
		 	  fi
		 	  msg_out="\"$visName\" is a subfolder of $parent"
	 	  	echo "$line $visName $parent" >> folders.index
		 	else
		 		# this line is a file
				msg_out="\"$visName\" is a file in folder $parent"
				echo "$line $visName $parent" >> files.index
			fi
	 	  if [[ $ARG == *"v"* ]]; then
	 	  	echo "$msg_out" | tee -a $LOG
	 	  else
	 	  	echo -n "."				# echo w/o newline
			fi
		done < "$OUTPUTDIR/index"
		echo
		# folders.index now has all the folders information
		# let's get it sorted
		# Read lines from folders.index file
		while IFS=' ' read -r id folder parent_id; do
		  folders_array["$id"]="$folder $parent_id"
		done < folders.index

		# Construct the associative array with full paths
		for key in "${!folders_array[@]}"; do
		  folders_array["$key"]=$(build_full_path "$key")
		done

		# Print the associative array. This is a test only
		if [[ $ARG == *"v"* ]]; then
			for key in "${!folders_array[@]}"; do
				echo "ID: $key, Full Path: ${folders_array[$key]}" | tee -a $LOG
			done
		fi
		
		# Now we have an array of all folders
		
		# Create all folders
		echo "Creating folder structure and downloading files" | tee -a $LOG
		
		# Now iterate through files.index and download to the right folder
		mapfile -t lines < "files.index"
		for line in "${lines[@]}"; do
			id=$(echo "$line" | awk '{print $1}')
			folderID=$(echo "$line" | awk '{print $3}')
			filename=$(echo "$line" | awk '{print $2}')
			# echo "$folderID"
			folder=${folders_array["$folderID"]}
			mkdir -p "$OUTPUTDIR/$folder"
			cd "$OUTPUTDIR/$folder"
			if [[ $ARG == *"v"* ]]; then
				echo "$folder/$filename" | tee -a $LOG
		  	echo "curl -s -O -J \"http://$RMIP/download/$id/placeholder\"" >> $LOG 
				curl -# -O -J "http://$RMIP/download/$id/placeholder"			# -> progress bar
			else
				echo -n "."
				curl -s -O -J "http://$RMIP/download/$id/placeholder"			# -s -> silent mode
			fi
			if [ $? -ne 0 ]; then
				ERRORREASON=$ERRORREASON$'\n Download failed'
				ERROR=1
			fi
		done
		echo				# make sure we add a newline
		echo "DOWNLOAD END" | tee -a $LOG
	fi
	
	if [[ $ARG == *"u"* ]]; then
		# Start upload
		echo "BEGIN UPLOAD" | tee -a $LOG
 		for file in "$UPLOADDIR"*;
 		do
 			[ -e "$file" ] || continue
 			echo -n "$(basename "$file"): " | tee -a $LOG											# echo without newline, because
 			curl --form "file=@\"$file\"" http://$RMIP/upload | tee -a $LOG		# this will output resulting status
			if [ 0 -eq $? ]; then rm "$file"; fi;
			echo "." | tee -a $LOG																						# Ensure a new line is added
 		done
 		if [ $? -ne 0 ]; then
 			ERRORREASON=$ERRORREASON$'\n Upload failed'
 			ERROR=1
 		fi
		echo "UPLOAD END" | tee -a $LOG
	fi

else
  echo "reMarkable not connected" | tee -a $LOG
  ERRORREASON="$ERRORREASON\n reMarkable not connected"
  ERROR=1
fi

# Capture the end time
end_time=$(date +%s.%N)
# Calculate the elapsed time
elapsed_time=$(echo "$end_time - $start_time" | bc)
# Output the elapsed time
echo "Time consumed: $elapsed_time seconds" | tee -a $LOG
# log date and time
echo "Time: $(date)" | tee -a $LOG

# notify user of completion
if typeset -f notification > /dev/null; then
  if [ $ERROR ]; then
    notification "ERROR in rM Sync!" "$ERRORREASON"
    echo "ERROR in rm Sync!"
  else
    notification "rM Sync successfull" "!"
    echo "rm Sync successfull!"
  fi
fi

# Feedback
echo "You might need to restart your reMarkable."
read -p "End of Script. <ENTER>" input
