#!/bin/bash

usage="\

Usage: backup.sh [OPTIONS] ...

This program zip your home folder to temp dir and encrypt it with openssl aes-256-cbc 
then it copies it to external drive if pluged in. Use this program to create an encrypted 
home folder backup file. In order to upload it on the MEGA and make a copy on sperate drive.

User is asked to provide the name of the hard drive (optional) then a password for file encryption. 
then the credentials for MEGA account

The backup file are not meant by default to be stored locally on device (default dir /tmp).
Use -f to change backup directory

  -f path  Change path of baskup directory 

  -h  Display help message

  -x excpluded_files Path of excluded files that will not be backup
"

end_message=$(cat <<'EOF'
 _______________________________________  
< All tasks completed. Have a nice day !>
 ---------------------------------------
   \
    \
        .--.
       |o_o |
       |:_/ |
      //   \ \
     (|     | )
    /'\_   _/`\
    \___)=(___/
EOF
)

is_installed=false

current_date=$(date +"%d-%m-%Y")
log_date=$(date "+%Y-%m-%d %H:%M:%S")
log_folder="$HOME/.config/backup"
log_file="$log_folder/log"

#Setting files variables
ziped_file="/tmp/home_bak.zip"
backup_folder="/tmp"
backup_file="$backup_folder/home_bak_$current_date"

if ! [ -e "$log_folder" ]; then
    mkdir "$log_folder" 
fi

if ! [ -e "$log_file" ]; then
    touch "$log_file"
    echo "$log_date : creating log file" >> "$log_file"
fi

while getopts "hf:x:" args; do
    case "${args}" in
      h)
        echo "$usage" 
        echo "$log_date : display help message" >> "log_file"
        exit 0
      ;;
      f)
        backup_folder="$OPTARG"

        if ! [ -e "$backup_folder" ]; then
          echo "No such file or directory" >&2
          exit 1
        fi

        backup_file="$backup_folder/home_bak_$current_date"
      ;;
      x)
        excpluded_files="$OPTARG"
      ;;
      *)
        echo "Invalid argument" >&2
        exit 1
    esac 
done

echo -e "Thanks for using this program ! \n"
echo -e "In order to proceed in creating an encrypted backup you first need to have a MEGA account. \n"
read -p  "I already have a MEGA account: Type y to continue. If not type n to stop program: " mega_account

if ! [ "$mega_account" = "y" ]; then
    echo -e "You can go create a MEGA account at this URL: https://mega.nz/login \n"
    exit 0
fi

#Checking dependencies
echo -e "Checking dependencies ... \n"
(apt list --installed | grep megatools) && (apt list --installed | grep megacmd) && is_installed=true

#Ask user to install dependencies if error occurs 
if "$is_installed"; then
    echo -e "dependencies OK \n" 
  else
    echo -e "ERROR: The following packages need to be installed: \n megatools megacmd \n" >&2
    echo -e "Also consider creating MEGA account if you have not already \n"
    read -p "Do you want to install them ? (y/n) Default n: " install_dependencies
    if ! [ "$install_dependencies" = "y" ]; then
      echo -e "Exitting \n" && exit 0
    else
      sudo apt update && sudo apt install megatools megacmd -y || echo -e "$log_date : Problem during install \n" >> "$log_file" && exit 1
      echo -e "Installation successful \n" 
      echo "$log_date : backup installing dependencies" >> "$log_file"
    fi
fi

#Setting path variables
current_dir="$PWD"
target_dir="$HOME"
home_dir_size="$(du -sb "$target_dir" | cut -f1)"

if [ "$home_dir_size" -ge 21474836480 ]; then
  echo -e "Home dir size too large exeeding 20 Giga Bytes \n" >&2 >> "$log_file" && exit 1
fi

drive_names=$(ls /media/"$USER"/)

if [ -z "$drive_names" ]; then
    echo -e "No hard drive found ! \n" 
  else
    echo -e "Found: \n ${drive_names} "
    read -p "Enter name of external hard drive: " drive_name
    external_drive_dir="/media/$USER/$drive_name/"
fi

#Giving fake name for external_drive_dir if user press enter and give bad name for hard drive
if [ -z "$drive_name" ]; then 
    external_drive_dir="/does_not_exists"
fi

#Checking if path exists if not user is asked to stop the program
if [ -e "$external_drive_dir" ]; then
    echo -e "Successfully assigned path for external drive ! \n"
  else
    read -p "Could not find path for external drive. Data will not be backed up on drive. Do you want to stop. Default yes (y/n)" answer
    if ! [ "$answer" = "n" ]; then
      echo -e "Exitting \n"
      exit 0
    fi
fi

#Setting password variables
password="none"
echo -e "Need to provide a pasword for encryption \n"

#Verify if both passwords match. Loops until it does 
until [ "$password" = "$second_password" ]; do
    echo -e "Type password. If prompt appears again this means passwords do not match \n"
    echo -e "! Do not mistype pasword or you won't be able to recover your backup ! \n"
    echo "Enter password:"
    read -s password
    echo "Re Enter password:"
    read -s second_password
done

echo -e "Password accepted \n"

#Setting credentials for MEGA
read -p "Enter your MEGA email: " email
read -s -p "Enter your MEGA password: " mega_password
echo

#login to MEGA
mega-login "$email" "$mega_password"

#Check if login was successful
if [ $? -ne 0 ]; then
    echo "Login to MEGA failed! Please check your credentials."
    echo "$log_date : backup failed to log to MEGA" >> "$log_file"
    exit 1
  else
    echo -e "Login successful ! \n"
    echo "$log_date : backup login to MEGA" >> "$log_file"
fi

#Checks if the current dir is home dir. If not changing to home dir
if ! [ "$current_dir" = "$target_dir" ]; then
    echo -e "Wrong directory \n" >&2
    echo -e "Changing directory ... \n"
    cd "$target_dir" || echo -e "Unable to move to home dir \n" >> "$log_file" && exit 1
fi

echo -e "Everything is fine ! You can now have coffe break. The program will go on \n"

#Compressing command
echo -e "Compressing home folder (this might take a while) ... \n"
zip -rq "$ziped_file" . -x ".local/*" ".cache/*" ".mozilla/*" "share/*" "firefox/*" "snap/*" ".icons/*" "backup_home/*" "$excpluded_files" 2>> "$log_file"
echo "$log_date : backup zip file created" >> "$log_file"

if ! [ -e "$ziped_file" ]; then
    echo -e "ERROR: ziped file not created. Exitting \n"  
    echo "$log_date : backup failed to create zip file" >> "$log_file"
    exit 1
fi

#Encrypting backup with openssl
openssl enc -e -aes-256-ctr -salt -pbkdf2 -iter 10000 -in "$ziped_file" -out "$backup_file" -k "$password"

if ! [ -e "$backup_file" ]; then
    echo -e "ERROR: backup file not created. Exitting \n"  
    echo "$log_date : backup failed to create backup file" >> "$log_file"
    exit 1
fi

echo "$log_date : backup encrypted file created" >> "$log_file"
rm "$ziped_file" #Removing zip file
chmod 700 "$backup_file" #Changing permissions to RWX only for owner

echo -e "Backup completed need to upload to MEGA. \n"

#Copying file to hard drive 
if [ -e "$external_drive_dir" ]; then
  echo -e "Copying to external drive ... \n"
  cp -p "$backup_file" "$external_drive_dir"
  echo -e "Finished \n" 
  echo "$log_date : backup file copied to external drive" >> "$log_file"
  else
    echo -e "External drive not pluged in or directory cannot be found \n"
    echo "$log_date : backup failed to copy backup to external drive" >> "$log_file"
fi

#Searching for old backup files
echo -e "Removing old backup file ... \n"
files_to_delete=$(mega-find | grep "home_bak_")

#Removing outdated backup
if [ -n "$files_to_delete" ]; then
    for file in $files_to_delete; do
        mega-rm "$file"
        echo "Deleted: $file"
        echo "$log_date : backup old backup deleted from MEGA $file" >> "$log_file"
    done
else
    echo -e "No file to remove \n"
fi

#Upload file
mega-put "$backup_file" 
echo "$log_date : backup uploaded backup to MEGA $backup_file" >> "$log_file"

#Checking if upload failed 
if [ $? -eq 0 ]; then
    echo "File uploaded successfully!"
  else
    echo "File upload failed!"
    echo "$log_date : backup failed to upload backup $backup_file" >> "$log_file"
fi

#Loging out
mega-logout
echo "$log_date : backup loging out MEGA" >> "$log_file"

if ! [ $? -eq 0 ]; then
    echo -e "Warning: Error while loging out. Consider loging out manually ! \n"
    echo -e "Log out command: mega-logout \n"
    echo "$log_date : backup failed loging out of MEGA" >> "$log_file"
fi

echo "$end_message"
echo "$log_date : backup program finished without errors" >> "$log_file"

