#!/bin/bash
# multipath I/O qemu VM script
#
# Default SPICE port: 5901
# Network Backend: user networking
#
# Required files/directories:
#  current-vars.bin - copy from the ovmf package
#  disk.img - created by qemu-img
#  mpio.img - created by qemu-img
#  tpm/
#  share/

ARGS=$@

UEFI_CODE_FILE="/usr/share/qemu/ovmf-x86_64-ms-4m-code.bin"
UEFI_VARS_FILE="current-vars.bin"
UEFI_CODE="-drive if=pflash,format=raw,readonly=on,file=$UEFI_CODE_FILE"
UEFI_VARS="-drive if=pflash,format=raw,file=$UEFI_VARS_FILE"

KVM=-enable-kvm
#KVM=

NET_USER="-netdev user,id=hostnet0 -device virtio-net-pci,netdev=hostnet0"
NET=$NET_USER

MACH="-machine type=q35"
CPU="-smp 4"

# SPICE
SPICE_PORT=5901
DISPLAY="-vga qxl \
	-spice port=${SPICE_PORT},addr=127.0.0.1,disable-ticketing=on"
#  Set up vdagent for copy&paste between host and guest, dynamic resolution
#  changes, etc.
DISPLAY="${DISPLAY} \
	-device virtio-serial \
	-chardev spicevmc,id=vdagent,debug=0,name=vdagent \
	-device virtserialport,chardev=vdagent,name=com.redhat.spice.0"

HDD_IMG="disk.img"
MPIO_IMG="mpio.img"

# Attach 2 disks to 1 image file with the same serial to emulate multipath I/O
MULTIPATH_HDDS="\
	-device virtio-scsi-pci,id=scsi \
	-drive if=none,id=disk1,file=${MPIO_IMG},cache=none,file.locking=off \
	-device scsi-hd,drive=disk1,serial=MPIO \
	-drive if=none,id=disk2,file=${MPIO_IMG},cache=none,file.locking=off \
	-device scsi-hd,drive=disk2,serial=MPIO \
"

HARDDRIVE="-drive file=$HDD_IMG ${MULTIPATH_HDDS}"
MEMORY="-m 4096"

TPMDIR=$(pwd)/tpm
TPMSOCK=${TPMDIR}/swtpm-sock
TPM2="--tpm2"

# Start swtpm
swtpm socket $TPM2 --tpmstate dir=$TPMDIR \
	--ctrl type=unixio,path=$TPMSOCK \
	--log file=swtpm.log,level=20 \
	-d

TPM="-chardev socket,id=chrtpm,path=$TPMSOCK \
     -tpmdev emulator,id=tpm0,chardev=chrtpm \
     -device tpm-tis,tpmdev=tpm0"

# mount -t 9p -o trans=virtio v_share share -oversion=9p2000.L
SHARE_FS="-virtfs local,id=fsdev,path=share,security_model=mapped-file,mount_tag=v_share"
#SHARE_FS="-drive file=fat:share/,format=raw,read-only,if=virtio"

RNG_DEV="-device virtio-rng-pci"

qemu-system-x86_64 $KVM \
		   -s \
		   -S \
		   $UEFI_CODE \
		   $UEFI_VARS \
		   $CPU \
		   $MACH \
		   $DISPLAY \
		   $HARDDRIVE \
		   $MEMORY \
		   $TPM \
		   $SHARE_FS \
		   -monitor stdio \
		   -debugcon file:debug.log -global isa-debugcon.iobase=0x402 \
		   -serial file:serial.log \
		   $RNG_DEV \
		   $NET \
		   $ARGS
