# Packer Windows

This repository contains a Packer file and scripts for building machine images from Windows ISOs.

## Windows ISO

Currently, Windows evaluation ISOs are locked behind your Microsoft ID, so it is not possible to download them automatically.

You'll need to go to the [Windows Evaluation Center website](https://www.microsoft.com/en-us/evalcenter/evaluate-windows-server-2019) and download the ISO for Windows Server 2019 to a location accessible by the Packer scripts.

## VirtIO Drivers

To allow Windows to access the virtual drives it needs to have the [VirtIO](https://github.com/virtio-win/virtio-win-pkg-scripts) drivers installed.

To do this, we mount the [latest stable ISO](https://fedorapeople.org/groups/virt/virtio-win/direct-downloads/stable-virtio/virtio-win.iso) for the virtio-win drivers to the virtual machine.

TODO: Do we need to add a script to the answers file to install them automatically?

# Building

```bash
$ PACKER_LOG=1 packer build \
    -var iso_url=/root/17763.737.190906-2324.rs5_release_svc_refresh_SERVER_EVAL_x64FRE_en-us_1.iso \
    -var iso_checksum=40db12a748abf8053edf540a776617e58966facf19b06069bf1b7ec2dbfd2621dc3385885c5ec6917556d867881761c6579e4b6551acf9cc526bf9ae726c88d6 \
    windows.pkr.hcl
```

Note that you may see several warnings from Packer about the WinRM connection being reset while Windows is installing, this may occur for some times (12m on my machine from initial boot till winrm connection ready). You may also see some 401 invalid content type errors that occur while the installer does the initial reboot and the OS is starting before it's ran the WinRM configuration script.

Frustratingly Windows doesn't immediately run the commands in `Autounattend.xml` after the initial reboot, so after the initial installation and reboot it may take several minutes for WinRM to connect and start running the provisioning scripts.


## Monitoring 

The Packer script is configured to disable the GTK GUI that shows the build process so that the build process can be run on a headless build server.

You can still monitor the build process remotely by noting down the VNC port in the Packer command output, opening an SSH tunnel (i.e. `ssh root@<ip address> -L <vnc port>:localhost:<vnc port>`) and then using a VNC client to connect to the VNC port.

> On Mac, you can use the built-in VNC viewer by opening the Screen Sharing app and connecting to the VNC port (i.e. `vnc://localhost:<vnc port>`).
>
> However, I had issues with it not actually connecting to the unsecured VNC server and had to use the RealVNC client instead.

> Pressing Alt (or Cmd) + Ctrl + 2 will switch to a QEMU debug console.

# Build Process

## Overview

  1. Packer launches a QEMU VM with the Windows ISO mounted.
  2. Windows detects the `Autounattend.xml` file and automatically configures and installs the operating system.
     1. Loads the Windows virtio drivers to enable virtual drive and networking support.
     2. Configures the installation disk partitions.
     3. Configures additional Windows components to make the server experience smoother.
     4. Configures the username and password of the administrator account.
     5. Runs initial setup commands to:
        1. Enable powershell script execution.
        2. Enable WinRM to allow Packer to connect and run provisioners.
        3. Enable utility features:
           1. Show file extensions in Explorer
           2. Show administration tools in Start Menu
           3. Disable hibernation
           4. Disable password expiration for administrator account
  3. Packer runs the provisioner scripts to configure the VM.
     1. Enables Remote Desktop Protocol (RDP) to allow remote access to the VM.

# Testing

To see if the VM image was created correctly I used a Nomad job that runs QEMU. To get it to work correctly, you'll need to add the output directory from the Packer build to the Nomad config as an allowed volume directory:
```hcl
# /etc/nomad.d/qemu.hck
plugin "qemu" {
  config {
    image_paths = ["/root/packer-windows/output-windowsserver"]
  }
}
```

And then run the Nomad job:
```bash
nomad run windows.nomad 
```

After 30s or so you should be able to connect to the VM using RDP, to get the RDP port note the allocation ID in the Nomad job output and run:
```bash
$ nomad alloc status <alloc id>

ID                  = <alloc id>
Eval ID             = <eval id>
Name                = windows-vm.vm[0]
Node ID             = <node id>
Node Name           = chaos
Job ID              = windows-vm
Job Version         = 10
Client Status       = running
Client Description  = Tasks are running
Desired Status      = run
Desired Description = <none>
Created             = 1h17m ago
Modified            = 1h17m ago
Deployment ID       = <deployment id>
Deployment Health   = healthy

Allocation Addresses
Label   Dynamic  Address
*rdp    yes      <ip>:<port>
*winrm  yes      <ip>:<port>
```

And look for the IP and port assigned in the allocation addresses section.

> The RDP username and password is `packer` and `packer` by default, based on the values specified in `install/Autounattend.xml`. If you change the password or username in the `Autounattend.xml` file, you'll need to change the winrm username and password in the Packer template file to allow Packer to remote in and provision the image.

# Debugging

## Windows Drives

If you get to the Windows install screen (via VNC) but there is an error due to there not being an installation drive, or there are missing drivers then open a command line with Shift+F10 and run:
```bash
wmic logicaldisk get caption
```
To list all the available drives, then you can use `dir` to list the directory contents of each drive till you find the virtio driver ISO.
```bash
X: \›dir F:
 Volume in drive F is virtio-win-0.1.217
 Volume Serial Number is BF1C-C74D

 Directory of F:l

04/13/2022 11:18 PM <DIR> Balloon
04/13/2022 11:18 PM <DIR> NetKVM
04/13/2022 11:19 PM <DIR> amd64
04/13/2022 11:19 PM <DIR> data
04/13/2022 11:18 PM <DIR> fwefg
04/13/2022 11:27 PM <DIR> guest-agent
04/13/2022 11:19 PM <DIR> i386
04/13/2022 11:18 PM <DIR> pvpanic
04/13/2022 11:18 PM <DIR> gemufwcfg
04/13/2022 11:18 PM <DIR> qemupciserial
...
```

Now that we know the F: drive is the correct drive, we can update `install/Autounattend.xml` to point to the correct drive letter.

# References

  * https://www.virtualizor.com/docs/admin/create-os-template/
  * https://www.packer.io/plugins/builders/qemu
  * https://github.com/chef/bento/blob/2dd9de689ce35cfae2515487c8b33f41f393bf95/packer_templates/windows/windows-2019.json
  * https://github.com/jakobadam/packer-qemu-templates/tree/master/windows
  * https://github.com/joefitzgerald/packer-windows

# TODO

  * Add cloud-init support sp we can reused the same pre-configured image for multiple VMs without needing to perform a full Windows install each time.