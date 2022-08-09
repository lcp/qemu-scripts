#!/bin/bash
# general qemu VM script
#
# Default SPICE port: 5901
#
# Required files/directories:
#  current-vars.bin - copy from the ovmf package
#  disk.img - created by qemu-img
#  tpm/
#  share/

ARGS=$@

UEFI_CODE_FILE="/usr/share/qemu/ovmf-x86_64-ms-4m-code.bin"
UEFI_VARS_FILE="current-vars.bin"
UEFI_CODE="-drive if=pflash,format=raw,readonly=on,file=$UEFI_CODE_FILE"
UEFI_VARS="-drive if=pflash,format=raw,file=$UEFI_VARS_FILE"

KVM=-enable-kvm
#KVM=

# Manually wire tap0 to br0:
#  # ip tuntap add mode tap user gary name tap0
#  # ip link set tap0 up
#  # ip link set tap0 master br0
NET_TAP="-netdev tap,id=hostnet0,ifname=tap0,script=no,downscript=no -device virtio-net-pci,netdev=hostnet0"
NET="$NET_TAP -net nic -net user"

MACH="-machine type=q35"
CPU="-smp 4"

# SPICE
SPICE_PORT=5901
GFX="-vga qxl \
     -spice port=${SPICE_PORT},addr=127.0.0.1,disable-ticketing=on"
#  Set up vdagent for copy&paste between host and guest, dynamic resolution
#  changes, etc.
GFX="${GFX} \
     -device virtio-serial \
     -chardev spicevmc,id=vdagent,debug=0,name=vdagent \
     -device virtserialport,chardev=vdagent,name=com.redhat.spice.0"

HDD_IMG="disk.img"

HARDDRIVE="-device virtio-scsi-pci,id=scsi \
           -drive if=none,id=disk1,file=${HDD_IMG} \
           -device scsi-hd,drive=disk1"

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
		   $GFX \
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
