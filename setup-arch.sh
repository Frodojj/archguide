#!/bin/bash -e
# Copyright 2025 Jimmy Cerra 
# license - Permission granted to use without restriction as long as the above
# copyright and this license are included with all whole or substantial copies.
# PROVIDED "as is" WITH NO WARRANTY. THE AUTHORS ARE NOT LIABLE FOR DAMAGES.

iwd_wifi() {
	local passphrase ssid
	read -p "Wifi Network SSID: " ssid
	read -p "Passphrase: " passphrase
	iwctl --passphrase "$passphrase" station wlan0 connect "$ssid"
}

nm_wifi() {
	local name passphrase ssid zone
	read -p "Wifi Network SSID: " ssid
	read -p "Passphrase: " passphrase
	firewall-cmd --list-all-zones | less
	read -p "Firewall zone: " zone
	nmcli connection add type wifi ssid "$ssid" \
		wifi-sec.key-mgmt wpa-psk wifi-sec.psk "$passphrase" \
		connection.id "$ssid" connection.mdns yes connection.zone "$zone"
	nmcli device wifi connect "$ssid"
}

# usage: prompt_comment pattern file
prompt_comment() {
	local ans pattern
	# escape pattern
	pattern="$(sed 's:[]\[^$.*/]:\\&:g' <<< "$1")"
	if [[ "$1" =~ ^# ]]; then
		read -p "Uncomment $1 (y/N)? " ans
		if [[ "$ans" =~ ^[Yy] ]]; then
			# remove # at front
			sed '/'"$pattern"'/s/^#//g' -i "$2"
		fi
	else
		read -p "Comment $1 (y/N)? " ans
		if [[ "$ans" =~ ^[Yy] ]]; then
			# add # at front
			sed '/'"$pattern"'/s/^/#/g' -i "$2"
		fi
	fi
}

# usage: prompt_filter file
prompt_filter() {
	local pattern
	read -p 'Enter pattern to filter file: ' pattern
	# Remove comment lines that are actual comments i.e.
	# 1. A line beginning with # and followed by a space
	# 2. A line with only a #
	# Then filter file and read into array.
	grep -ve '^#[[:space:]]' -e '^#$' "$1" | grep -e "$pattern" -	 
}

# usage: prompt_hostname hostname_path
prompt_hostname() {
	local name
	read -p 'Enter hostname (allowed: hyphen - and lowercase a-z): ' name
	echo "$name" > "$1"
}

# usage: prompt_new_user root_path
prompt_new_user() {
	local username
	# Show commands and quit if a program doesn't work
	read -p 'Enter user name: ' username
	useradd -m -G wheel --root "$1"	"$username"
	passwd --root "$1" "$username"
}

# Uncomments prompted locales in locale.gen and writes default to locale.conf
# usage: lgselect gen_path conf_path
lgselect() {
	local cont loc loc2
	local -a available_locales
	local -a selected_locales
	until [[ "$cont" =~ ^[Nn] ]]; do
		echo 'Locale select' >&2
		readarray -t available_locales < <(prompt_filter "$1")
		echo 'Select locale: ' >&2
		select loc in "${available_locales[@]}" "Cancel"; do
			if [ "$loc" == "Cancel" ]; then
				# Go back
				break
			elif [ "$loc" ]; then
				prompt_comment "$loc" "$1"
				break
			else
				echo 'Please select a valid number: ' >&2
			fi
		done
		read -p 'Select again (Y/n)? ' cont
	done
	 
	readarray -t selected_locales < <(grep -v -e '^#' "$1")
	echo 'Select default: ' >&2
	select loc2 in "${selected_locales[@]}"; do
		if [ "$loc2" ]; then
			echo "LANG=$loc2" | cut -d' ' -f1 > "$2"
			break
		else
			echo 'Please select a valid number: ' >&2
		fi
	done
}

setup_drive() {
	local ssd_path=/dev/nvme0n1
	local efi_path=/dev/nvme0n1p1
	local root_path=/dev/nvme0n1p2
	
	# Erase drive
	#echo -n "PSID" | cryptsetup erase -v --hw-opal-factory-reset /dev/nvme0n1 -d -
	cryptsetup erase -v --hw-opal-factory-reset "$ssd_path"

	#Partition drive
	# nvme0n1p1: type is EFI System
	# nvme0n1p2: size os all available, GUID is Linux root (x86-64)
	sfdisk "$ssd_path" <<- EOF
		label: gpt
		size=4GiB, type=uefi
		size=+, type=4F68BCE3-E8CD-4DB1-96E7-FBCAF984B709
	EOF

	# Display drive partitions
	lsblk

	# Encrypt root partition
	cryptsetup -v luksFormat --hw-opal-only "$root_path"
	cryptsetup open "$root_path" root

	# Format partitions
	mkfs.ext4 /dev/mapper/root
	mount /dev/mapper/root /mnt
	mkfs.fat -F32 "$efi_path"
	mount --mkdir -o fmask=0077,dmask=0077 "$efi_path" /mnt/boot
}

setup_files() {
	# Time
	ln -sf "/mnt/usr/share/zoneinfo/$(tzselect)" /mnt/etc/localtime
	hwclock --systohc --adjfile=/mnt/etc/adjtime
	mkdir /mnt/etc/systemd/timesyncd.conf.d/
	cat > /mnt/etc/systemd/timesyncd.conf.d/01_ntp.conf <<- EOF
		[Time]
		NTP=0.us.pool.ntp.org 1.us.pool.ntp.org 2.us.pool.ntp.org 3.us.pool.ntp.org
		FallbackNTP=0.arch.pool.ntp.org 1.arch.pool.ntp.org 2.arch.pool.ntp.org 3.arch.pool.ntp.org
	EOF

	# Localization
	lgselect /mnt/etc/locale.gen /mnt/etc/locale.conf
	touch /mnt/etc/vconsole.conf

	# Network
	prompt_hostname /mnt/etc/hostname

	# Sudo TODO is this best? Use visudo?
	# Verified no syntax errors with visudo -c -f - << EOF...
	cat > /mnt/etc/sudoers.d/01_config <<- EOF
		%wheel ALL=(ALL:ALL) ALL
		Defaults editor=/usr/bin/rnano
		Defaults pwfeedback
		Defaults umask=0022
		Defaults umask_override
	EOF

	# Make file have correct permissions
	chmod 0640 /mnt/etc/sudoers.d/01_config
	chown root:root /mnt/etc/sudoers.d/01_config

	# Verify correct
	visudo -cf /mnt/etc/sudoers.d/01_config

	# Swapfile
	fallocate -l 16GB /mnt/swapfile
	chmod 600 /mnt/swapfile
	mkswap /mnt/swapfile
	swapon /mnt/swapfile
	cat > /mnt/etc/systemd/system/swapfile.swap <<- EOF
		[Swap]
		What=/swapfile

		[Install]
		WantedBy=swap.target
	EOF

	# Configure initial ramdisk & kernel hooks
	echo 'HOOKS=(base systemd autodetect microcode modconf kms' \
		'keyboard sd-vconsole sd-encrypt block filesystems fsck)' \
		> /mnt/etc/mkinitcpio.conf.d/myhooks.conf

	# Comment _image lines, uncomment _uki lines and rename /efi to /boot
	sed '/_uki/ {s|^#|| ; s|/efi|/boot|}' -i /mnt/etc/mkinitcpio.d/linux.preset
	sed '/_image/ s/^/#/' -i /mnt/etc/mkinitcpio.d/linux.preset

	# Setup root password
	echo 'Enter root password' >&2
	passwd --root /mnt
	
	prompt_new_user /mnt
}

setup_system() {
	# Localization
	arch-chroot /mnt locale-gen

	# Install bootloader
	arch-chroot /mnt bootctl install

	# Regenerate initial ramdisk
	arch-chroot /mnt mkinitcpio -P

	# Enable services
	arch-chroot /mnt systemctl enable firewalld gpm NetworkManager \
		swapfile.swap systemd-boot-update systemd-resolved systemd-timesyncd
}

install() {
	setup_drive

	pacstrap -K /mnt base linux linux-firmware intel-ucode \
		alsa-utils bash-completion firewalld gpm man-db man-pages nano \
		networkmanager sbctl sudo tpm2-tss udiskie
		
	setup_files

	setup_system

	swapoff /mnt/swapfile
	umount -R /mnt
	
	echo 'Instructions for secure boot:'
	echo 'Reboot into UEFI/BIOS.'
	echo 'Put secure boot into setup mode.'
	echo "Don't enable secure boot yet."
	echo "Then log in and run: ${0##*/} secure_boot"
}

secure_boot() {
	sbctl create-keys
	
	sbctl enroll-keys -m
	
	sbctl verify 2> /dev/null | \
		sed -n $'s/\u2717 /sbctl sign -s / ; s/ is not signed$//e'
	
	sbctl sign -s -o \
		/usr/lib/systemd/boot/efi/systemd-bootx64.efi.signed \
		/usr/lib/systemd/boot/efi/systemd-bootx64.efi
	
	echo 'Instructions for enrolling unlock key into TPM2:'
	echo 'Reboot into UEFI/BIOS.'
	echo 'Enable secure boot.'
	echo "Then log in and run: ${0##*/} enroll_tpm"
}

enroll_tpm() {
	systemd-cryptenroll /dev/nvme0n1p2 --recovery-key > recovery-key
	
	echo "Recovery key written to file: recovery-key"
	
	systemd-cryptenroll /dev/nvme0n1p2 \
		--wipe-slot=empty --tpm2-device=auto --tpm2-pcrs=7
}

# CLI

cli() {
	case "$1" in 
		"iwd_wifi")
			iwd_wifi
			;;
		"nm_wifi")
			nm_wifi
			;;
		"install") 
			install
			;;
		"secure_boot")
			secure_boot
			;;
		"enroll_tpm")
			enroll_tpm
			;;
		*)
			cat <<- EOF
				Usage: ${0##*/} COMMAND
				Commands:
				 iwd_wifi     Connect to wifi with iwd 
				 nm_wifi      Setup wifi in Network Manager
				              Connects to wifi with Network Manager
				 install      Partitions drive into /boot (EFI) and / (Root)
				              Installs system
				              Writes configuration files
				              Runs configuring programs in new system
				 secure_boot  Sets up Secure Boot
				 enroll_tpm   Creates recovery key & enrolls keys into TPM2
				              Writes key to file: recovery-key
				              Erases empty passwords
			EOF
	esac
}

cli "$1"