# Basic Machine Parameters

To launch a VM with QEMU, there are some basic parameters:

* `-enable-kvm`: enable the KVM acceleration
* `-smp <number>`: specify the CPU number
* `-m <number>`: the memory size in MB
* `-M <machine>`: the machine type. For the modern x86_64 VM, "q35" is a reasonable choice.

Then we can launch a VM with 4 CPUs and 8GB RAM like this:

    $ qemu-system-x86_64 \
      -enable-kvm \
      -smp 4 \
      -m 8192 \
      -M q35 \
      ...

# System Firmware

## BIOS (SeaBIOS)

By default, QEMU launches x86 VMs with its default BIOS, SeaBIOS. You can specify a SeaBIOS
firmware file with "-bios /path/to/bios.bin".

## UEFI (OVMF)

For the physical machines, UEFI is stored in NVRAM. QEMU emulates NVRAM with "pflash".
There are two parts of UEFI: the read-only code part and the writeable variable store.
For SLE/openSUSE, the UEFI firmware files are in "/usr/share/qemu/", and there are
various flavors, and the details of flavors are in "/usr/share/doc/packages/ovmf/README".
For the common testing, we just choose the "ms-4m" flavor. The "code" part is read-only,
so it's fine to use the system file. However, the "vars" part should be writeable, so we
should copy the file from the system folder like this:

    $ cp /usr/share/qemu/ovmf-x86_64-ms-4m-vars.bin /home/user/my-vm/my-vm-vars.bin

Then, we launch the VM with the following parameters:

    $ qemu-system-x86_64 \
      ...
      -drive if=pflash,format=raw,readonly=on,file=/usr/share/qemu/ovmf-x86_64-ms-4m-code.bin \
      -drive if=pflash,format=raw,file=/home/user/my-vm/my-vm-vars.bin \
      ...

In case you want to check the debug messages of OVMF, just add this the debugcon:

    $ qemu-system-x86_64 \
      ...
      -debugcon file:debug.log -global isa-debugcon.iobase=0x402 \
      ...

Then the OVMF debug messages will go to "debug.log" file.

# Block Device

## Disk and CDROM Emulation

A block device would be necessary if you want to install an OS into the VM. For a quick start,
you can just use `-drive` and the `file` parameter:

    $ qemu-system-x86_64 \
      ...
      -drive file=my-vm-disk.img \
      ...

This command creates a SATA disk associated with my-vm-disk.img. NOTE: the default disk
interface is IDE in the old QEMU version.

In case you want to add multiple disks to the VM, you may consider to add the index to each
disk:

    $ qemu-system-x86_64 \
      ...
      -drive file=my-vm-disk0.img,index=0 \
      -drive file=my-vm-disk1.img,index=1 \
      -drive file=my-vm-disk2.img,index=2 \
      -drive file=my-vm-disk3.img,index=3 \
      ...

Then those disk images will become `sda`, `sdb`, `sdc`, and `sdd` in the guest VM.

The default media type of a block device is "disk", and you can create a CDROM like this:

    $ qemu-system-x86_64 \
      ...
      -drive file=my-vm-cd.iso,index=2,media=cdrom \
      ...

Besides the local image files, it is also possible to use a remote image files for the
emulated disks. For more details, please check [QEMU block drivers reference](https://www.qemu.org/docs/master/system/qemu-block-drivers.html).

## Multipath I/O Emulation

It is worthwhile to mention that QEMU can emulate Multipath I/O with one disk image file.
Assume that we have a image called my-mpio.img, we can assign two disks with the same serial
to the image, and then those two disks will be recognized as multipath I/O disks.

    $ qemu-system-x86_64 \
      ...
      -device virtio-scsi-pci,id=scsi \
      -drive if=none,id=disk1,file=my-mpio.img,cache=none,file.locking=off \
      -device scsi-hd,drive=disk1,serial=MPIO \
      -drive if=none,id=disk2,file=my-mpio.img,cache=none,file.locking=off \
      -device scsi-hd,drive=disk2,serial=MPIO \

Since multipath I/O is defined in the SCSI spec, we need to add a SCSI controller and attach
those two disks to the controller. Please remember to disable file lock with
"file.locking=off" so that the second disk won't fail due to the locking on the image file.

# Network Device

QEMU can emulate several network cards, and we can check the supported cards in the
"Network devices" section from this command:

    $ qemu-system-x86_64 -device help

For a Linux guest, "virtio-net-pci" is usually the best choice due to the better performance
and support in both Linux kernel and OVMF.

Besides the network device, you also have to choose the network backend. The network device
is about how the guest interacts with the VM, and the network backend is about how the VM
interacts with the host.

There are two common used network backends: User Networking and TAP.

## User Networking (SLIRP)

If you launch the VM with a normal user, SLIRP is the easiest backend to use. SLIRP implements
a virtual NAT, and it's provides DHCP, DNS, tftp, and even SMB services. By default, SLIRP
assigns IP 10.0.2.15 to the guest and the guest can access the host with the IP 10.0.2.2.
For a simple combination of virtio-net-pci + SLIRP:

    $ qemu-system-x86_64 \
      ...
      -netdev user,id=hostnet0 -device virtio-net-pci,netdev=hostnet0 \
      ...

Here we declare a user networking backend with id, hostnet0, and assign it for a
*virtio-net-pci* device.

In case you want to do a quick test of the PXE Boot config, you can directly set the tftp
root directory and the bootfile to SLIRP like this:

    $ qemu-system-x86_64 \
      ...
      -netdev user,id=hostnet0,tftp=/home/user/tftproot,bootfile=/bootx64.efi \
      -device virtio-net-pci,netdev=hostnet0 \
      ...

After launching the VM and choosing PXE boot entry, the SLIRP DHCP sends the download location
of /home/user/tftproot/bootx64.efi so that the firmware (OVMF or SeaBIOS) can download the
bootloader through tftp.

For the Windows guest, it's convenient to share the host folder through SMB, i.e. Network
Neighborhood.

    $ qemu-system-x86_64 \
      ...
      -netdev user,id=hostnet0,smb=/home/user/share \
      -device virtio-net-pci,netdev=hostnet0 \
      ...

Just assign the folder to share to 'smb' and then the guest can access the folder through the
SMB protocol with the IP 10.0.2.4.

Altought SLIRP is convenient, there are some limitations:

* the network performance is poor due to the overhead
* ICMP, i.e. ping, doesn't work in the guest
* the host and the external network cannot directly access the guest

Thus, SLIRP is usually for testing, not for production.

## TAP

The TAP network backend is based on Linux kernel TAP device. Since TAP directly works with
Ethernet frames, it provides better performance. On the other hand, creating a TAP requires
root privilege. Even so, it's possible to create a TAP device for a specific user.
For example:

    # ip tuntap add mode tap user johndoe name tap0

This command creates a TAP device named as tap0 and assigns the control to the user, johndoe.
Then, you can assign tap0 to a the network device like this:

    $ qemu-system-x86_64 \
      ...
      -netdev tap,id=hostnet0,ifname=tap0,script=no,downscript=no \
      -device virtio-net-pci,netdev=hostnet0 \
      ...

With this config, anything that the guest sends to the virtio-net device goes to the host
through tap0 and vice versa. Unlike SLIRP, there are no default DHCP and DNS services for
the TAP backend, so the user has to configure the network settings. For example, if we want
the host and guest can communicate each other in the subnet, 192.168.0.x/24, then we can
set 192.168.0.1/24 to tap0 and configure 192.168.0.2/24 to the virtio-net device in the guest.

NOTE: Please check your firewall rule after creating a TAP device since the default rule may
unexpected block your network service on the TAP device.

In the real world, a TAP device is usually managed by a bridge device which also manages one
physical network device, so that the TAP device can send/receive packets through the physical
network device. This is also how libvirt manages the guest network devices.

To attach a TAP device to a bridge, just use this 'ip' command:

    # ip link set tap0 master br0

Then, tap0 will be under the control of br0.

For more details of QEMU networking, please see [QEMU Networking](https://wiki.qemu.org/Documentation/Networking).

# File Sharing

There are several methods to share files between the guest and the host, and there are
two catagories: local file systems and networking file systems.

## Local File Systems

### Read-only FAT Partition

It's possible to emulate a specific folder as a read-only FAT partition.

    $ qemu-system-x86_64 \
      ...
      -drive file=fat:/home/user/my-vm/share/,format=raw,read-only,if=virtio \
      ...

Then, the guest will see an additional FAT partition with the files inside
"/home/user/my-vm/share/". Since FAT is widely supported even in UEFI, it almost guarantees
the files can be read by the guest. However, the downside is the partition is read-only for
the guest and won't be synchronized after the guest is relaunched. Anyway, it is still a
convenient method for testing UEFI images such as shim.efi or grub.efi with a read-only FAT
partition.

### VirtFS

VirtFS is a special file system for QEMU guest. The guest can mount the specific folder in the
host with the read-write access. To use VirtFS, the VM has to be launched with the following
parameters:

    $ qemu-system-x86_64 \
      ...
      -virtfs local,id=fsdev,path=/home/user/my-vm/share,security_model=mapped,mount_tag=v_share
      ...

Then a VirtFS with tag, `v_share`, is associated with "/home/user/my-vm/share", and the guest
can mount the file system with the `v_share` tag like this:

    # mount -t 9p -o trans=virtio v_share /home/user/share -oversion=9p2000.L

Since VirtFS is based on "Plan 9 Filesystem Protocol", the guest OS has to support "9p"
file system driver. Unfortunately, RHEL doesn't support 9p file system so VirtFS won't work
in RHEL guest.

For more details about VirtFS, please check [QEMU 9psetup](https://wiki.qemu.org/Documentation/9psetup).

## Networking File Systems

If the guest is configured with a network device, then it may be a good idea to share files
with networking file systems. SSHFS could be a convenient solution since it only requires the
host to enable ssh daemon. For the VM configured with SLIRP, the built-in SMB server
(as mentioned in the SLIRP section) could be a cheap solution. If the above methods don't
apply to your case, NFS may be another solution. It only requires to configure NFS server
in the host. Please check the distribution document for the NFS server setup.
