# pi-boot-script

#### Run your own startup scripts on Raspbian, without ever having touched the Linux partition.

This is a 100% script-based way to run commands at boot. It only uses the FAT32 */boot* partition on the SD card or the .img file. You don't need to change anything about the ext4 (Linux) partition.

This is useful if:

* you want to do unattended configuration at the first boot of the new SD card. For example, to configure networking, hostname, localisation and SSH; to create and resize partitions; and to install packages
* you broke something in the operating system, and just need to remove that *one* file to get it running again
* you write a lot of SD cards and don't want to spend time configuring each one
* you prefer to use the pristine Linux partition, rather than a modified version from someone you don't know
* you prefer a readable and editable shell script over a compiled program.

Doing it only with the */boot* partition is attractive because Macs and PCs don't easily write to the Linux partition. Who wants to install yet another program on their computer?

## Usage
Each of these can be done on an SD card with Raspbian or on the downloaded *.img* disk image, which you can then flash to any number of SD cards. Most computers auto-mount the */boot* partition when you insert the SD card or double-click the *.img* file.

From very limited to an elaborate configuration:
### Basic: just run a few shell commands
This requires the *unattended* file and a change to the file *cmdline.txt* on the boot partition.

1. Download the file [unattended](./unattended) from this project
2. Open the file for editing. Look at section 2: remove what is there, and put your commands there. \*
3. Save the file and put it on the boot partition. Now open *cmdline.txt*, which is already on that partition \*\*
4. Remove the item with `init=` (if it is there) and put the following at the end of the line:

```ini
init=/bin/bash -c "mount -t proc proc /proc; mount -t sysfs sys /sys; mount /boot; source /boot/unattended"
```
5. Save the file, eject the SD card or .img file, and you're done.

***Example***: at section 2 of *unattended*, you could put the command

```bash
raspi-config nonint do_hostname MyLittlePi
```
to change the hostname of the Pi.

\* when your commands run, the PATH is `/usr/local/bin:/usr/local/sbin:/usr/bin:/usr/sbin:/bin:/sbin:.`; the entire Linux partition is available; systemd isn't up yet so there are no services, the network is unavailable, and the system thinks it's January 1st, 1970.

\*\* the [cmdline.txt](./cmdline.txt) in this project is from Raspbian Buster Lite 26-9-2019. If you happen to have that version, you can drop my cmdline.txt in.

### Medium: copy files over to the Linux partition
This time you can leave the *unattended* file unchanged; it was written to move files over.

1. Put all the files in a directory *payload/* in a subdirectory equivalent to where they will be on the Pi:
    * a file *payload/etc/hosts* will become */etc/hosts* on the Pi
    * *payload/home/pi/.bashrc* will become */home/pi/.bashrc* in the user profile
2. Put the *payload/* folder in the boot partition
3. Also put *unattended* there
4. Open *cmdline.txt* on the boot partition, remove the item with `init=` (if it is there) and put the following at the end of the line:

```ini
init=/bin/bash -c "mount -t proc proc /proc; mount -t sysfs sys /sys; mount /boot; source /boot/unattended"
```
5. Save the file, eject the SD card or .img file, and you're done.

### Full: run configuration & installation scripts

For elaborate configuration it makes sense to run a script during a 'normal' boot. The *unattended* script takes care of that. This project has two scripts for normal-boot execution:

* *payload/usr/local/bin/one-time-script.sh* for configuration
* *payload/usr/local/bin/packages-script.sh* for installation of packages, using apt-get.

The way to proceed, after downloading the project, is:

1. Rewrite the scripts to your liking, or replace them with your own (or, if you like [what they do](#what-the-scripts-do), configure them in *one-time-script.conf*)
2. Put any other files that you want to copy to the root filesystem, in the corresponding place in *payload/*, e.g. if you want */var/opt/myfile* on the Pi, you create *payload/var/opt/myfile*.
3. Copy files over to the boot partition:
    * *unattended*
    * *one-time-script.conf* (if you made any changes to it)
    * the *payload* folder with the scripts and all the other things you want to put on the Pi
4. Open *cmdline.txt* on the boot partition, remove the item with `init=` (if it is there) and put the following at the end of the line:

```ini
init=/bin/bash -c "mount -t proc proc /proc; mount -t sysfs sys /sys; mount /boot; source /boot/unattended"
```
5. Eject the SD card or .img file \*\*\*

You now have an SD card that will self-configure when put into a Pi, or you have an .img file that can be flashed to an unlimited number of SD cards which will all self-configure when put in a Pi.

If you're using the .img file, every time you have flashed an SD card with it you can open */boot/one-time-script.conf* on the SD card, to do some configuration for that particular card.

\*\*\* If you mounted the card or image from a Mac, you might like to remove some trash first: in Terminal,

```bash
find /Volumes/boot/payload/ -name '._*' -delete
find /Volumes/boot/payload/ -name '.DS_Store' -delete
```

I'm not sure what kind of trash Windows puts in.

#### What the scripts do
The scripts write log messages to */boot/configuration.log*.
The script *one-time-script.sh* in its current form does the following:

* create and format an additional FAT32 partition, configuring it to be owned by the user *pi* for writing application logs etc.
* make the Linux partition take up the remaining space on the card
* set hidden files in /home/pi (if any were moved there) as non-executable, and SSH public keys as private
* set the timezone
* set the hostname, based on the hardware generation and CPU serial number: a Pi 3 with serial 2c45df gets hostname *pi3-2c45df*. Or if NEW_HOSTNAME_COMPANY was set to *enron*, the hostname becomes *pi3-enron-2c45df*
* turn SSH on
* set the WIFi country
* solve a locale-mixing problem for SSH logins (warnings like `locale: Cannot set LC_CTYPE to default locale: No such file or directory` when you open a manpage or install a package)
* set the default way of booting (console or desktop, auto-login or prompt)
* change the locale
* write some data about the card and the operating system to a file on the boot partition
* disable itself for future boots, enable the package installation script, reboot

Then *packages-script.sh* does this:

* update the package lists
* install a bunch of packages
* if given the URL, install a recent version of Node.js
* disable itself from running again
* reboot.

## Warnings and recovery
Obviously you wouldn't do this sort of thing to an SD card that holds all your most important files, or that is urgently needed in a production situation. Remember that all of these scripts are all-powerful: they run as the administrator, so `rm -rf /` will *really* erase everything.

If you have overwritten *cmdline.txt* on the boot partition with another version and booting is impossible, copy the cmdline.txt from the *.img* file. Or if you don't have that, correct the partition UUID in cmdline.txt:

* find the disk UUID, 4 bytes at offset 0x1b8 from the start of the SD card or .img, with a command like

      ```
      sudo dd if=/dev/disk2 bs=4 skip=110 count=1 | hexdump
      ```
      
      which would display its result as `00000000  57 4a 2e 40` (example value, for 2017-04-10-raspbian-jessie).
* take the four bytes in reverse order (it is a little-endian system), append `-02` for the root partition, and put the result in *cmdline.txt* in the form `root=PARTUUID=402e4a57-02`

## References
I first described this at [StackExchange](https://raspberrypi.stackexchange.com/a/105534/94485) and the [Raspberry Pi Forums](https://www.raspberrypi.org/forums/viewtopic.php?p=1567588#p1567588). Some inspiration has come from Raspbian's built-in [partition resizing script](https://github.com/RPi-Distro/raspi-config/blob/master/init_resize.sh), in particular the mounting commands that make the script run.



