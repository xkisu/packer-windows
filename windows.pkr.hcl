variable "iso_url" {
  type = string
}

variable "iso_checksum" {
  type = string
}

source "qemu" "windowsserver" {
  # https://software-download.microsoft.com/download/pr/17763.737.190906-2324.rs5_release_svc_refresh_SERVER_EVAL_x64FRE_en-us_1.iso
  iso_url           = var.iso_url
  iso_checksum      = var.iso_checksum

  # Disables showing the GUI with the installation process.
  #
  # The installation process will still be available via VNC
  # if you make a note of the VNC display number chosen, and
  # then connect using `vncviewer -Shared <host>:<display>`.
  headless = true

  # Specifies the format and size of the image disk.
  #
  # Note that Windows Server 2019 requires at least
  # 9695MB of disk space for the installation.
  disk_size         = "10G"
  format            = "qcow2" # Format of the generated image

  # Use KVM acceleration for the virtual machine.
  accelerator       = "kvm" # Use KVM Acceleration

  # Specifies the interface used to mount the disk.
  # Note that in this setup, this is irrelevant, as
  # we manually build the mount command in `qemuargs`.
  disk_interface = "virtio"

  # Specifies the memory size of the VM
  # for installation in megabytes.
  #
  # If this value is too small then the
  # installation may fail with code
  # 0xc0000017
  #
  # A higher value will allow the installation
  # to complete faster, but it will use more
  # memory.
  memory = 4000 # 4GB

  # Mount files and scripts that are required
  # by the Windows installation.
  floppy_files = [
    "./install/Autounattend.xml",
    "./install/winrm.ps1",
  ]

  # Add additional custom args to the qemu command.
  qemuargs = [
    # Mount the virtio driver ISO as an additional CDROM drive.
    #
    # The Autounattend script is setup to automatically install
    # the appropriate drivers from the ISO.
    #
    # See: https://wiki.archlinux.org/title/QEMU#Preparing_a_Windows_guest
    [ "-drive", "file=${path.root}/drivers/virtio-win-0.1.217.iso,media=cdrom,index=3" ],

    # Adding the custom virtio drive will cause Packer to not populate
    # it's disk default args, so we manually add them back along with
    # specifying the drive indexes to known values.
    #
    # See: https://github.com/hashicorp/packer/issues/3348#issuecomment-605661528
    [ "-drive", "file=output-windowsserver/packer-windowsserver,if=virtio,cache=writeback,discard=ignore,format=qcow2,index=1" ],
    [ "-drive", "file=${var.iso_url},media=cdrom" ] # Installer ISO
  ]

  #  output_directory  = "output_centos_tdhtest"
  shutdown_command  = "shutdown /s /t 10 /f /d p:4:1 /c \"Packer Shutdown\""

  #  vm_name           = "tdhtest"
  #  net_device        = "virtio-net"

  # How long Packer waits before assuming the VM has booted.
  #
  # I set this to the average time it takes for Windows to
  # install and configure it's self to avoid excessive
  # messages from timeouts and errors while booting.
  boot_wait = "10m"

  # Configure the builder to use WinRM instead
  # of SSH to communicate with the guest VM.
  communicator   = "winrm"
  winrm_username = "packer"
  winrm_password = "packer"
  winrm_insecure = true
  winrm_use_ssl  = true # uses port 5986 when true, otherwise 5985
  winrm_timeout = "30m" # Set to high value as Windows install can take awhile to be ready

  # It appears that if Packer connects to WinRM
  # too quickly after it's enabled that the
  # commands Packer sends don't get executed.
  #
  # TODO: Is this really needed? I'm not sure.
  #  It seems inconsistent whether the commands
  #  run correctly immediately after enabling
  #  WinRM or not.
  pause_before_connecting = "1m30s"
}

build {
  sources = ["source.qemu.windowsserver"]

  # Use a shell provisioner to perform any additional
  # configuration or installation on the image.
  provisioner "windows-shell" {
    scripts = [
      "./scripts/enable-rdp.bat"

      # TODO: Disable WinRM and remove firewall port after provisioning
    ]
  }
}