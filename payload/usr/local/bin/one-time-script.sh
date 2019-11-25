#!/bin/bash
# Start script for unattended configuration of a Raspberry Pi

# 1. INTERNAL SCRIPT BUSINESS
# logging of the script's run
logfile=configuration.log
templog=/dev/shm/$logfile
log() {
	echo "$@" >> $templog;
}
endscript() {
	# Write the log to the boot partition 
	date > /boot/$logfile
	cat $templog >> /boot/$logfile
	reboot
}
log "Unattended configuration by $0";
exec 2>>$templog;	# log all errors

# parameters - first the default values...
NEW_PARTITION_SIZE_MB=288
NEW_PARTITION_LABEL='config'
NEW_LOCALE='en_GB.UTF-8'
NEW_TIMEZONE='Europe/Amsterdam'
NEW_HOSTNAME_COMPANY=''
NEW_SSH_SETTING=0
NEW_WIFI_COUNTRY=NL
NEW_WIFI_SSID="Our network"
NEW_WIFI_PASSWORD="Secret password"
NEW_BOOT_BEHAVIOUR=B1
NEW_SD_CARD_NUMBER=XX
NODE_JS_SOURCE_URL=""
PACKAGES_TO_INSTALL=()

# ...then see if values can be read from a file, then remove that (may contain password)
# but save parameters for the next script back to the file
if [[ -f /boot/one-time-script.conf ]]; then
	source /boot/one-time-script.conf && log "Read parameters from /boot/one-time-script.conf";
	echo "NODE_JS_SOURCE_URL='$NODE_JS_SOURCE_URL'" > /boot/one-time-script.conf;
	echo "PACKAGES_TO_INSTALL=(${PACKAGES_TO_INSTALL[@]})" >> /boot/one-time-script.conf;
else
	log "Using default parameters";
fi;

# stop this service from running at boot again
log -n "Remove automatic running of config script: ";
systemctl disable one-time-script.service && log OK || log FAILED;

# prepare for the package installation script to run on the next boot
log -n "Set up automatic running of package installation script: ";
systemctl enable packages-script.service && log OK || log FAILED;


# 2. DISK MANAGEMENT
log $'\nDISK MANAGEMENT';
# create another FAT32 partition
ROOT_PART=$(mount | sed -n 's|^/dev/\(.*\) on / .*|\1|p')
PART_NUM=${ROOT_PART#mmcblk0p}
LAST_PARTITION=$(parted /dev/mmcblk0 -ms unit s p | tail -n 1 | tr -d 's')
LAST_PART_NUM=$(echo "$LAST_PARTITION" | cut -f 1 -d:)
if [[ "$PART_NUM" -ne 2 || $LAST_PART_NUM -ne 2 ]]; then
	log "Did not find the standard partition scheme. Aborting"
	endscript
fi
ROOT_PART_END=$(echo "$LAST_PARTITION" | cut -d ":" -f 3)
ROOT_DEV_SIZE=$(cat /sys/block/mmcblk0/size)	
if ((ROOT_PART_END + 2048*NEW_PARTITION_SIZE_MB >= ROOT_DEV_SIZE)); then
	log "Not enough free space for a $NEW_PARTITION_SIZE_MB MB partition. Aborting"
	endscript
fi
log -n "Create new FAT32 entry in the partition table: "
fdisk /dev/mmcblk0 <<END
n
p
3
$((ROOT_DEV_SIZE - 2048*NEW_PARTITION_SIZE_MB))
$((ROOT_DEV_SIZE - 1))
t
3
C
w
END
[[ $? -eq 0 ]] && log OK || log FAILED

# format the new partition
log -n "Format the new partition as FAT32: "
mkfs.fat -F 32 -n $NEW_PARTITION_LABEL /dev/mmcblk0p3 && log OK || log FAILED;

# make sure it is owned by user pi, so it can write to it
log -n "Add the new partition to /etc/fstab for mounting at boot: "
PART_UUID=$(grep vfat /etc/fstab | sed -E 's|^(\S+)\S .*|\1|;q')3 &&\
echo "$PART_UUID  /$NEW_PARTITION_LABEL  vfat  defaults,uid=1000,gid=1000  0  2" >> /etc/fstab && log OK || log FAILED;

# enlarge the ext4 partition and filesystem
log -n "Make the ext4 partition take up the remainder of the SD card: "
parted -m /dev/mmcblk0 u s resizepart 2 $((ROOT_DEV_SIZE-2048*NEW_PARTITION_SIZE_MB-1)) && log OK || log FAILED;
log -n "Resize the ext4 file system to take up the full partition: "
resize2fs /dev/mmcblk0p2 && log OK || log FAILED;


# 3. PI USER PROFILE SETUP
# doing this before OS config because until reboot, sudo is confused by a new hostname
log $'\nPI USER PROFILE SETUP';
chmod a+w $templog
cd /tmp
sudo -u pi /bin/bash <<-END
	echo -n "Unsetting executable-bits of hidden files: " >> $templog;
	find /home/pi -type f -name '.*' -exec chmod -x \{\} + && echo OK >> $templog || echo FAILED >> $templog;
	if [[ -f /home/pi/.ssh/authorized_keys ]]; then
		echo -n "Making authorized ssh keys private: " >> $templog;
		chmod 0600 /home/pi/.ssh/authorized_keys && chmod 0700 /home/pi/.ssh && echo OK >> $templog || echo FAILED >> $templog;
	fi;
END


# 4. OPERATING SYSTEM CONFIGURATION
log $'\nOPERATING SYSTEM CONFIGURATION';
log -n "Change timezone: "
raspi-config nonint do_change_timezone "$NEW_TIMEZONE" && log OK || log FAILED;

modelnr=$(sed -E 's/Raspberry Pi ([^ ]+).*/\1/' /proc/device-tree/model);
serial=$(grep ^Serial /proc/cpuinfo | sed -E 's/^.*: .{10}//');
[[ $NEW_HOSTNAME_COMPANY ]] && hname="pi$modelnr-$NEW_HOSTNAME_COMPANY-$serial" || hname="pi$modelnr-$serial";
log -n "Set hostname to $hname: "
raspi-config nonint do_hostname "$hname" && log OK || log FAILED;

log -n "Set SSH to "  # 0 = on, 1 = off
[[ $NEW_SSH_SETTING == 0 ]] && log -n "on: " || log -n "off: ";
raspi-config nonint do_ssh $NEW_SSH_SETTING && log OK || log FAILED;

log -n "Set WiFi country: "
raspi-config nonint do_wifi_country $NEW_WIFI_COUNTRY && log OK || log FAILED;

log -n "Set WiFi login: "
raspi-config nonint do_wifi_ssid_passphrase "$NEW_WIFI_SSID" "$NEW_WIFI_PASSWORD" && log OK || log FAILED;

log -n "Avoid language setting problems when logged in through SSH: "
sed -i 's/^AcceptEnv LANG LC_\*/#AcceptEnv LANG LC_*/' /etc/ssh/sshd_config && log OK || log FAILED;

log -n "Set standard boot to text console without auto-login: "
raspi-config nonint do_boot_behaviour $NEW_BOOT_BEHAVIOUR && log OK || log FAILED;

log -n "Change locale: "
raspi-config nonint do_change_locale "$NEW_LOCALE" && log OK || log FAILED;


# 5. WRITE SOME SYSTEM DATA TO A FILE ON /BOOT
log $'\nWRITE SOME SYSTEM DATA TO A FILE ON /BOOT';
kernel_info=$(uname -a);
debianv=$(cat /etc/debian_version);
distro_name=$(lsb_release -ds 2>/dev/null);
distro_code=$(sed -n -E 's/^.*stage([[:digit:]]).*$/\1/p' /boot/issue.txt 2>/dev/null);
case $distro_code in
	1) distr=mimimal;;
	2) distr=lite;;
	3) distr="base-desktop";;
	4) distr="small-desktop";;
	5) distr=desktop;;
	*) distr="";;
esac;
card=$(udevadm info -a -n mmcblk0 | grep ATTRS{serial} | sed -E 's/.*x(\w{8}).*/\1/');
cardfiles=(/boot/SD-*);
if [[ -f ${cardfiles[0]} ]]; then
	cardnr=$(sed -E 's|/boot/SD[^0-9]+([0-9]+).txt|\1|' <<<${cardfiles[0]});
else
	cardnr=$NEW_SD_CARD_NUMBER;
fi;
/bin/cat > "/boot/SD-card-$cardnr.txt" <<-END
	SD card nr $cardnr with serial number $card
	$distro_name $distr
	(Debian $debianv)
	$kernel_info
END
[[ $? -eq 0 ]] && log OK || log FAILED


endscript
