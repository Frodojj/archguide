#!/bin/bash -e
# Copyright 2025 Jimmy Cerra 
# MIT license: Permission granted to use without restriction as long as the
# copyright and license are included with all whole or substantial copies.
# PROVIDED "AS IS" WITH NO WARRANTY. THE AUTHOR(S) ARE NOT LIABLE FOR DAMAGES.

# echo_hostname hostname_path
echo_hostname() {
	local name
	read -p 'Enter hostname (allowed: hyphen - and lowercase a-z): ' name
	echo "$name" > "$1"
}

# echo_locale gen_path conf_path
echo_locale() {
	local loc
	local -a selected_locales
	readarray -t selected_locales < <(grep -v -e '^#' "$1")
	echo 'Select default: ' >&2
	select loc in "${selected_locales[@]}"; do
		if [ "$loc" ]; then
			echo "LANG=$loc2" | cut -d' ' -f1 > "$2"
			break
		else
			echo 'Please select a valid number: ' >&2
		fi
	done
}

# install_dictionaries gen_path
install_dictionaries() {
	local loc
	local -a selected_locales
	readarray -t selected_locales < <(grep -v -e '^#' "$1")
	for loc in "${selected_locales[@]}"
	do
		echo 'Install language package: ' >&2
		install_pattern "aspell-${loc:0:2}"
		echo 'Install language package: ' >&2
		install_pattern "hunspell-${loc:0:2}"
	done
}

# install_pattern pattern 
install_pattern() {
	local package
	local -a packages
	readarray -t packages < <(pacman -Ssq "$1")
	select package in "${packages[@]}" "Cancel"; do
		if [ "$package" == "Cancel" ]; then
			echo 'Canceled' >&2
			break
		elif [ "$package" ]; then
			pacman -S "$package"
			break
		else
			echo 'Please select a valid number: ' >&2
		fi
	done
}

# Uncomments locales in locale.gen and writes default to locale.conf
# lgselect gen_path
lgselect() {
	local cont='y'
	local -a selected_locales
	until [[ "$cont" =~ ^[Nn] ]]; do
		toggle_locale "$1"
		read -p 'Select again (Y/n)? ' cont
	done
}

# search file
search() {
	local pattern=''
	read -p "Pattern to search in file: " pattern
	# Remove comment lines that are actual comments i.e.
	# 1. A line beginning with # and followed by a space
	# 2. A line with only a #
	# Then filter file and read into array.
	grep -ve '^#[[:space:]]' -e '^#$' "$1" | grep -e "$pattern" -	 
}

# toggle_comment pattern file
toggle_comment() {
	local ans='N' pattern=''
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

# toggle_locale file
toggle_locale() {
	local loc
	local -a available_locales
	echo 'Search locales (i.e. en)' >&2
	readarray -t available_locales < <(search "$1")
	echo 'Select number to uncomment/comment: ' >&2
	select loc in "${available_locales[@]}" "Cancel"; do
		if [ "$loc" == "Cancel" ]; then
			echo 'Canceled' >&2
			break
		elif [ "$loc" ]; then
			toggle_comment "$loc" "$1"
			break
		else
			echo 'Please select a valid number: ' >&2
		fi
	done
}

# command: enroll_tpm RECOVERY_KEY_FILE
enroll_tpm() {
	systemd-cryptenroll /dev/nvme0n1p2 --recovery-key | tee "$1"
	
	echo "Recovery key written to file: $1" >&2
	
	systemd-cryptenroll /dev/nvme0n1p2 \
		--wipe-slot=empty --tpm2-device=auto --tpm2-pcrs=7
}

# command: help
help() {
	cat >&2 <<- EOF
		Usage: ${0##*/} COMMAND args
		Commands:
	EOF
	sed -n '/^# command: / s/^.\{10\}/ / p' "$0"
	cat >&2 <<- EOF
		Install Menu Commands:
	EOF
	sed -n '/^# menu command: / s/^.\{15\}/ / p' "$0"
}

# command: install
install() {
	local command
	local -a commands
	readarray -t commands < <(sed -n '/^# menu command: / s/^.\{16\}//p' "$0")
	select command in "${commands[@]}" "Cancel"; do
		"$command"
		break
	done
}


# command: install_gnome
install_gnome() {
	local base='gdm gnome-shell gnome-backgrounds gnome-control-center sushi'
	local apps='firefox gimp gnome-console gnome-text-editor handbrake loupe'
	local exts='gnome-browser-connection gnome-shell-extension-arc-menu'
	exts+=' gnome-shell-extension-dash-to-panel gnome-shell-extension-caffeine'
	exts+=' gnome-shell-extensions'

	pacman -S "$base $apps $exts"
}

# command: secure_boot
secure_boot() {
	sbctl create-keys

	sbctl enroll-keys -m

	sbctl verify 2> /dev/null | \
		sed -n $'s/\u2717 /sbctl sign -s / ; s/ is not signed$//e'

	sbctl sign -s -o \
		/usr/lib/systemd/boot/efi/systemd-bootx64.efi.signed \
		/usr/lib/systemd/boot/efi/systemd-bootx64.efi

	cat >&2 <<- EOF
		Instructions for enrolling SSD key into TPM2:
		Reboot into UEFI/BIOS.
		Enable secure boot.
		Then log in and run: ${0##*/} enroll_tpm ./RECOVERY_KEY_FILE
	EOF
}

# command: wifi iwd SSID PASSPHRASE
# command: wifi nm SSID PASSPHRASE FIREWALL_ZONE NAME
wifi() {
	if ["$1" == "iwd" ]; then
		iwctl --passphrase "$3" station wlan0 connect "$2"
	else
		nmcli connection add type wifi ssid "$2" \
			wifi-sec.key-mgmt wpa-psk wifi-sec.psk "$3" \
			connection.id "$5" connection.mdns yes connection.zone "$4"
		nmcli device wifi connect "$5"
	fi
}

# menu command: setup_ssd /dev/nvme0n1 /mnt
setup_ssd() {
	local -n ssd_path="$1"
	local -n mount_path="$2"
	local efi_path="$ssd_path"p1
	local root_path="$ssd_path"p2
	
	# Erase drive
	echo -n "E8UMGJ66CACU6BYXT6FLME4A4KHUNQMX" | \
		cryptsetup erase -v --hw-opal-factory-reset "$ssd_path" -d -
	#cryptsetup erase -v --hw-opal-factory-reset "$ssd_path"

	#Partition drive
	# nvme0n1p1: type is EFI System
	# nvme0n1p2: size os all available, GUID is Linux root (x86-64)
	sfdisk "$ssd_path" <<- EOF
		label: gpt
		size=4GiB, type=uefi
		size=+, type=4F68BCE3-E8CD-4DB1-96E7-FBCAF984B709
	EOF

	# Encrypt root partition
	cryptsetup -v luksFormat --hw-opal-only "$root_path"
	cryptsetup open "$root_path" root

	# Format partitions
	mkfs.ext4 /dev/mapper/root
	mount /dev/mapper/root "$mount_path"
	mkfs.fat -F32 "$efi_path"
	mount --mkdir -o fmask=0077,dmask=0077 "$efi_path" "$mount_path"/boot
}

# menu command: install_packages /mnt
install_packages() {
	local base='base linux linux-firmware sbctl tpm2-tss'
	local dev='base-devel git'
	local fonts='noto-fonts noto-fonts-cjk noto-fonts-emoji noto-fonts-extra'
	local help='man-db man-pages'
	local hw='bluez bluez-utils gpm intel-ucode'
	local net='avahi firewalld networkmanager nss-mdns openssh'
	local sound='alsa-utils helvum pipewire-alsa pipewire-pulse wireplumber'
	local utils='aspell bash-completion hunspell nano pacman-contrib sudo'
	
	pacstrap -K "$1" "$base $dev $fonts $help $hw $net $sound $utils"
}
	#  font-awesome ttf-nerd-fonts-symbols ttf-roboto
	# pipewire-pulse pipewire-jack	
	# hspell libvoikko 
	# gnome
	# 
	# dunst hyprland hyprlock hyprpaper hyprpicker hyprpolkitagent hypridle  
	# kitty network-manager-applet waybar xdg-desktop-portal-gtk   
	# xdg-desktop-portal-hyprland
	# 
	# qt5-wayland qt6-wayland   
	# rofi  copyq udiskie   

# menu command: setup_files /mnt
setup_files() {
	# Time
	ln -sf "$1/usr/share/zoneinfo/$(tzselect)" "$1/etc/localtime"
	hwclock --systohc --adjfile="$1/etc/adjtime"
	mkdir "$1/etc/systemd/timesyncd.conf.d/"
	cat > "$1/etc/systemd/timesyncd.conf.d/01_ntp.conf" <<- EOF
		[Time]
		NTP=0.us.pool.ntp.org 1.us.pool.ntp.org 2.us.pool.ntp.org 3.us.pool.ntp.org
		FallbackNTP=0.arch.pool.ntp.org 1.arch.pool.ntp.org 2.arch.pool.ntp.org 3.arch.pool.ntp.org
	EOF

	# Localization
	lgselect "$1/etc/locale.gen"
	echo_locale "$1/etc/locale.gen" "$1/etc/locale.conf"
	touch "$1/etc/vconsole.conf"

	# Network
	echo_hostname "$1/etc/hostname"
	sed '/hosts:/ s/mymachines/mymachines mdns_minimal [NOTFOUND=return]/' \
		-i "$1/etc/nsswitch.conf"
	cp "$1/usr/share/doc/avahi/ssh.service" "$1/etc/avahi/services/"

	# Verified no syntax errors with visudo -c -f - << EOF...
	cat > "$1/etc/sudoers.d/01_config" <<- EOF
		%wheel ALL=(ALL:ALL) ALL
		Defaults editor=/usr/bin/rnano
		Defaults pwfeedback
		Defaults umask=0022
		Defaults umask_override
	EOF

	# Make file have correct permissions
	chmod 0640 "$1/etc/sudoers.d/01_config"
	chown root:root "$1/etc/sudoers.d/01_config"

	# Verify correct
	visudo -cf "$1/etc/sudoers.d/01_config"

	# Swapfile
	fallocate -l 16GB "$1/swapfile"
	chmod 600 "$1/swapfile"
	mkswap "$1/swapfile"
	swapon "$1/swapfile"
	cat > "$1/etc/systemd/system/swapfile.swap" <<- EOF
		[Swap]
		What=/swapfile

		[Install]
		WantedBy=swap.target
	EOF
	swapoff "$1"/swapfile

	# Configure initial ramdisk & kernel hooks
	echo 'HOOKS=(base systemd autodetect microcode modconf kms' \
		'keyboard sd-vconsole sd-encrypt block filesystems fsck)' \
		> "$1/etc/mkinitcpio.conf.d/myhooks.conf"

	# Comment _image lines, uncomment _uki lines and rename /efi to /boot
	sed '/_uki/ {s|^#|| ; s|/efi|/boot|}' -i "$1/etc/mkinitcpio.d/linux.preset"
	sed '/_image/ s/^/#/' -i "$1/etc/mkinitcpio.d/linux.preset"
}

# menu command: setup_programs /mnt
setup_programs() {
	# Localization
	arch-chroot "$1" locale-gen
	
	# Install dictionaries
	install_dictionaries /etc/locale.gen

	# Install bootloader
	arch-chroot "$1" bootctl install

	# Regenerate initial ramdisk
	arch-chroot "$1" mkinitcpio -P

	# Enable services
	arch-chroot "$1" systemctl enable avahi-daemon bluetooth firewalld gpm \
		NetworkManager paccache.timer pacman-filesdb-refresh.timer sshd \
		swapfile.swap systemd-boot-update systemd-timesyncd
	# systemd-resolved
}

# menu command: setup_root /mnt
setup_root() {
	echo 'Enter root password' >&2
	passwd --root "$1"
}

# menu command: setup_user /mnt
setup_user() {
	local username
	read -p 'Enter user name: ' username
	useradd -m -G input,wheel --root "$1" "$username"
	passwd --root "$1" "$username"
}

# menu command: unmount_drive /mnt
unmount_drive() {
	umount -R "$1"
	
	cat >&2 <<- EOF
		Instructions for secure boot:
		Reboot into UEFI/BIOS.
		Put secure boot into setup mode.
		Don't enable secure boot yet.
		Then log in and run: ${0##*/} secure_boot
	EOF
}

"$@"
