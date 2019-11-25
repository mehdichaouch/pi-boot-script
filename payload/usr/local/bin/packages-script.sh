#!/bin/bash
# Start script for unattended package installation on a Raspberry Pi

# 1. INTERNAL SCRIPT BUSINESS
# logging of the script's run
logfile=configuration.log
templog=/dev/shm/$logfile
log() {
	echo "$@" >> $templog;
}
endscript() {
	# Append to the log on the boot partition 
	echo >> /boot/$logfile
	date >> /boot/$logfile
	cat $templog >> /boot/$logfile
	reboot
}
log "Unattended package installation by $0";
exec 2>>$templog;	# log all errors

# parameters - first the default values...
NODE_JS_SOURCE_URL=""
PACKAGES_TO_INSTALL=()

# ...then see if values can be read from a file, then remove that (may contain password)
[[ -f /boot/one-time-script.conf ]] && source /boot/one-time-script.conf &&\
 rm -f /boot/one-time-script.conf &&\
 log "Read parameters from /boot/one-time-script.conf" || log "Using default parameters";

# stop this service from running at boot again
log -n "Remove automatic running of package installation script: ";
systemctl disable packages-script.service && log OK || log FAILED;


# 6. PACKAGE INSTALLATION
log $'\nPACKAGE INSTALLATION';
export DEBIAN_FRONTEND=noninteractive	# avoid debconf error messages

log -n "Update APT package lists: "
apt-get update && log OK || log FAILED;

if [[ $NODE_JS_SOURCE_URL ]]; then
	log -n "Install nodejs: "
	curl -sL "$NODE_JS_SOURCE_URL" | bash - && apt-get install -y nodejs && log OK || log FAILED;
fi;

if [[ $PACKAGES_TO_INSTALL ]]; then
	log -n "Install ${PACKAGES_TO_INSTALL[0]}";
	for x in "${PACKAGES_TO_INSTALL[@]:1}"; do
		log -n ", $x";
	done;
	log -n ": ";
	apt-get install -y "${PACKAGES_TO_INSTALL[@]}" && log OK || log FAILED;
fi;


endscript