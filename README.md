Arch Install with Encrypted Root, Secure Boot, and TPM2
=======================================================

Before booting, you may need your OPAL PSID to factory reset the SSD. 
This is usually written on the SSD. (E.G. Look on bottom of Samsung 990
Pro with Heatsink.) Take a picture with your phone of the PSID for your 
records.

Configure install envionment
----------------------------

### Verify the boot mode
To verify the boot mode, check the UEFI bitness (should be 64):

	cat /sys/firmware/efi/fw_platform_size

### Connect to the internet
	iwctl --passphrase PASSPHRASE station wlan0 connect SSID

Make sure connected by running (press Ctrl-c to stop):

	ping archlinux.org

### Update the system clock
	timedatectl

Configure the SSD
-----------------

### Identify the SSD
To identify these devices, use lsblk or fdisk:

	lsblk
	fdisk -l

### Perform a secure disk erasure
SSDs with encryption are always encrypting their data even with no password
user password set. In this way, hardware encryption is "free" performance-wise
(though the implementation might still be vulnerable to hacking). 

If you don't know your SSD's OPAL Admin password, or if one was never set on a
new device, you should perform a secure disk erasure. The computer's 
firmware/UEFI/BIOS can sometimes help you set the Admin Password too. (Look 
under Security.)

To perform a factory reset/secure erasure, you'll need the OPAL PSID. The 
PSID is usually written on SSD. (Look on bottom of Samsung 990 Pro with 
Heatsink, for example). Don't foreget, resetting the device will reset
the OPAL password if it's set.

	cryptsetup erase -v --hw-opal-factory-reset /dev/nvme0n1

### Partition the disks
You may want to delete existing partitions first.
Use a partitioning tool like fdisk to modify partition tables:

	fdisk /dev/nvme0n1

Create table:

* g - Create a new GPT partition table
* n - Create new partition (EFI)
    - Accept default partition number 1
    - Accept default first sector
    - Enter "+4G" for last sector
* t - Change partition type
    - Partition 1 selected automatically
    - L to list all
    - q to exit back to partition type prompt
    - 1 EFI System
* n - Create new partition (Linux filesystem)
    - Accept defaults to use the remaining space
* t - Change partition type
    - Choose partition 2 or press enter
    - L to list all
    - q to exit back to partition type prompt 	
    - 23 Linux root (x86-64)
* w - Write changes and exit

Verify partitions, use lsblk or fdisk again:

	lsblk
	fdisk -l

### Encrypt ssd, format and mount partitions
Create and mount the encrypted root partition. The passphrase will be wiped 
later, so it's ok to use a blank one. However, you need to remember the 
OPAL Admin password that you set.

	cryptsetup -v luksFormat --hw-opal-only /dev/nvme0n1p2
	cryptsetup open /dev/nvme0n1p2 root

Format and mount encrypted root partition:

	mkfs.ext4 /dev/mapper/root
	mount /dev/mapper/root /mnt

Check the mapping works as intended:

	umount /mnt
	cryptsetup close root
	cryptsetup open /dev/nvme0n1p2 root
	mount /dev/mapper/root /mnt

Format and mount EFI Partition:

	mkfs.fat -F32 /dev/nvme0n1p1
	mount --mkdir /dev/nvme0n1p1 /mnt/boot

Install essential packages
--------------------------
	pacstrap -K /mnt base linux linux-firmware alsa-utils firewalld gpm intel-ucode man-db man-pages nano networkmanager sbctl sudo tpm2-tss

Enter the new system environment
--------------------------------
	arch-chroot /mnt

### Time
Set time zone:

	ln -sf "/usr/share/zoneinfo/$(tzselect)" /etc/localtime

Syncronize real-time clock:

	hwclock -w

Add NTP servers:

	mkdir /etc/systemd/timesyncd.conf.d/
	nano /etc/systemd/timesyncd.conf.d/01_ntp.conf

Example contents:

	[Time]
	NTP=0.us.pool.ntp.org 1.us.pool.ntp.org 2.us.pool.ntp.org 3.us.pool.ntp.org
	FallbackNTP=0.arch.pool.ntp.org 1.arch.pool.ntp.org 2.arch.pool.ntp.org 3.arch.pool.ntp.org

### Localization
Use `less /etc/local.gen` to see available options. Uncomment lines with
locales en_US.UTF-8 and others in locale.gen

	sed -i '/en_US.UTF-8/s/^#//' /etc/locale.gen
	sed -i '/es_US.UTF-8/s/^#//' /etc/locale.gen

Generate locales:

	locale-gen
	
Set locale config:

	echo 'LANG=en_US.UTF-8' > /etc/locale.conf

### Network
	echo 'COMPUTERNAME' > /etc/hostname

### Sudo setup
    EDITOR=nano visudo -f /etc/sudoers.d/01_config

Contents:

	%wheel ALL=(ALL:ALL) ALL
	Defaults editor=/usr/bin/rnano
	Defaults umask=0022
	Defaults umask_override

If you made a mistake, when you exit nano then you'll get a message like

	What now?

In that case, type `e` to go back and fix your mistake.

### Swapfile (16GB)
	fallocate -l 16GB /swapfile
	chmod 600 /swapfile
	mkswap /swapfile
	swapon /swapfile

Add to systemd:

	nano /etc/systemd/system/swapfile.swap

Contents:

	[Swap]
	What=/swapfile
	
	[Install]
	WantedBy=swap.target

Configure initial ramdisk & kernel hooks
-------------------------------------------------------------------
	nano /etc/mkinitcpio.conf
 
NOTE: ORDER IS IMPORTANT!!! Make sure has systemd, sd-vconsole, and 
sd-encrypt hooks. Example:

	HOOKS=(base systemd autodetect microcode modconf kms keyboard sd-vconsole keymap consolefont block sd-encrypt filesystems fsck)

Edit Preset file:

	nano /etc/mkinitcpio.d/linux.preset

Uncomment uki and comment image entries, replace start of path with `/boot`:

	#ALL_config="/etc/mkinitcpio.conf"
	ALL_kver="/boot/vmlinuz-linux"
	
	PRESETS=('default' 'fallback')
	
	#default_config="/etc/mkinitcpio.conf"
	#default_image="/boot/initramfs-linux.img"
	default_uki="/boot/EFI/Linux/arch-linux.efi"
	#default_options="--splash=/usr/share/systemd/bootctl/splash-arch.bmp"
	
	#fallback_config="/etc/mkinitcpio.conf"
	#fallback_image="/boot/initramfs-linux-fallback.img"
	fallback_uki="/boot/EFI/Linux/arch-linux-fallback.efi"
	fallback_options="-S autodetect"

Create /etc/vconsole.conf

	touch /etc/vconsole.conf

Install & Configure systemd-boot
--------------------------------
Install systemd-boot on the EFI partition:

	bootctl install

Regenerate initial ramdisk
--------------------------
	mkinitcpio -P

Setup users
-----------

### Set Root password
	passwd
	
### Make a new user
	useradd -m -G wheel USERNAME
	passwd USERNAME

Enable services
---------------
	systemctl enable firewalld
	systemctl enable gpm
	systemctl enable NetworkManager
	systemctl enable swapfile.swap
	systemctl enable systemd-boot-update
	systemctl enable systemd-resolved
	systemctl enable systemd-timesyncd
 
Reboot
------
Remove installation media before booting.

	exit
	swapoff /mnt/swapfile
	umount -a
	reboot

Secure Boot
-----------
Before starting, goto BIOS/UEFI put Secure Boot into Setup Mode. On some 
computers (like the GMKtec G3 Plus), you need to set an administrator
password for the BIOS/UEFI in order for Setup Mode to be available. Also
DISABLE the setting to Attempt Secure Boot, otherwise the boot will fail.

### Check secure boot status:

	sbctl status

### Create and enroll secure boot keys:

You may need root access. Just prepend sbctl with `sudo ` if so.

	sbctl create-keys
	sbctl enroll-keys -m

Check status is installed:

	sbctl status

### Check which files need signed:

	sbctl verify

### Sign all unsigned keys:
You may need root access again. Just prepend with sbctl with `sudo ` in both the command and in the sed script if so. If a lot of files need verified, use following:

	sbctl verify 2> /dev/null | \
 	sed -n $'s/\u2717 /sbctl sign -s / ; s/ is not signed$//e'

You can also sign them by hand individually like so:

	sbctl sign -s /boot/vmlinuz-linux
	sbctl sign -s /boot/EFI/BOOT/BOOTX64.EFI
	sbctl sign -s /boot/EFI/Linux/arch-linux-fallback.efi
	sbctl sign -s /boot/EFI/Linux/arch-linux.efi
	sbctl sign -s /boot/EFI/systemd/systemd-bootx64.efi

Verify no more files
 
	sbctl verify
 
Sign boot loader so automatically signs new files when linux kernel,
systemd, or boot loader updated:

	sbctl sign -s -o \
	/usr/lib/systemd/boot/efi/systemd-bootx64.efi.signed \
	/usr/lib/systemd/boot/efi/systemd-bootx64.efi

### Verify worked
	reboot
 
After rebooting, make sure UEFI/BIOS has secure boot turned on. Sometimes it is still turned off after booting into setup mode. Reboot and enter UEFI/BIOS to correct if you find that Secure Boot is disabled. 

	sbctl status

Enroll TPM
----------
The following may need root privlidges. Just prepend with `sudo ` as usual if so.

### Create recovery key.
Transcribe it to a safe place.

	systemd-cryptenroll /dev/nvme0n1p2 --recovery-key

### Enroll keys into TPM2.
Enter recovery key (with dashes) when asked for passphrase. Add `--tpm2-with-pin=yes` at end to require a pin to unlock drive:

	systemd-cryptenroll /dev/nvme0n1p2 --wipe-slot=empty --tpm2-device=auto --tpm2-pcrs=7

### Verify enrolled:

	cryptsetup luksDump /dev/nvme0n1p2

Look for `systemd-tpm2` entry under tokens.

### Reboot
	reboot

> May whatever God you believe in have mercy on your soul. - Q


Configure new system
--------------------

### Wifi connection
To setup without connecting until next boot, use the following:

	nmcli con add type wifi ssid SSID \
	wifi-sec.key wpa-psk wifi-sec.psk PASSPHRASE \
	con.id NAME con.mdns yes con.zone FIREWALLDZONE

To setup and connect right now, use:

	nmcli device wifi connect SSID password PASSPHRASE
	nmcli con modify SSID con.zone FIREWALLDZONE con.mdns yes

### Mouse support
This may not be necessary. My mouse was recognized without this step after logging in the first time.

Use `gpm -t help` to list supported mice. For example for Logitec mice:

	gpm -m /dev/input/mice -t logim

Tips
====

Keyboard shortcuts
------------------
* BASH defaults
    - Ctrl-k = cut to end of line
    - Ctrl-y = paste

* Nano defaults
    - Alt-Shift-A = start selecting text
    - Ctrl-k = cut selection or line if no selection
    - Ctrl-u = paste

BASH tips
---------
* This uncomments all:

		sed '/PATTERN/s/^#//g' -i FILE

	Explanation: searches for lines containing PATTERN and removes #
	from start of line. g means global; remove g for 1st instance only.

* This comments all:

		sed '/PATTERN/s/^/#/g' -i FILE

* BASH quotes:
    - 'text' is literal
    - "text" interprets $VARS \escapes \`tics\` and !history
    - $'\u2717 text' Interprets hex code unicode in the string escaped with \uXXXX

Checks
------

### Check Internet Connection
	ping archlinux.org

### Check Microcode
Microcode & CPU Family/Model/Stepping:

	journalctl -k --grep='CPU0:|microcode:'

For [Intel's Microcode](https://github.com/intel/Intel-Linux-Processor-Microcode-Data-Files),
goto the file `releasenote.md` in their repository.

### Check Security

#### Secure Boot
	sbctl status

#### TPM2
	cryptsetup luksDump /dev/nvme0n1p2

#### Firewall
	sudo firewall-cmd --get-active-zones

### Check Sound
	speaker-test -c 2

### Check Swap file

#### Ways to check if swap file is used
	swapon --show
	cat /proc/swaps

#### Ways to check if swap in memory
	vmstat
	free
	cat /proc/meminfo

### Check Time/Date status
	timedatectl
