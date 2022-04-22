# https://powersj.io/posts/ubuntu-qemu-cli/
# https://github.com/hashicorp/nomad/issues/5688

# https://wiki.archlinux.org/title/QEMU#Preparing_a_Windows_guest

job "windows-vm" {
  region      = "global"
  datacenters = ["dc1"]
  type        = "service"

  group "vm" {
    count = 1

    network {
      port "rdp" {}
      port "winrm" {}
    }

    ephemeral_disk {
      migrate = false
      size    = 5000
      sticky  = true
    }

    # Task to generate the cloud-init metadata NoCloud drive in the allocation directory.
    task "metadata" {
      lifecycle {
        hook = "prestart"
        sidecar = false
      }

      template {
        data = <<EOH
instance-id: iid-local01
local-hostname: cloudimg
EOH

        destination = "local/metadata.yaml"
      }
      template {
        data = <<EOH
#cloud-config
password: password
chpasswd:
  expire: False
ssh_pwauth: True
ssh_authorized_keys:
  - ssh-rsa AAAAB3NzaC1yc2EAAAADAQABAAABgQDZzKk+0wSbI41R9oOlClHs9YoMga5sxR337hBPuWRJd4sLTaTPCg90A8sNRTBAPGI623z+tubRuOYwkpfegTH7gjmOg6+W1uKxXMC+e2xGECofaaK0UfgICbHrMdR5FRfrIHH/dl$
EOH

        destination = "local/user-data.yaml"
      }

      driver = "docker"
      config {
        image = "ghcr.io/xkisu/docker-cloud-utils/cloud-utils:main"

        work_dir = "/metadata/local/"
        command = "cloud-localds"

        # Output the image to the shared allocation directory.
        args = ["/alloc/data/seed.img", "user-data.yaml", "metadata.yaml"]

        # Mount the task directory to the container to allow us
        # to read the metadata files generated from the templates
        # and to give us a place to save the generated image to.
        mount {
          type     = "bind"
          source   = "." # bind the task directory for this task
          target   = "/metadata/"
          readonly = false
        }

      }

    }

    task "vm" {
      driver = "qemu"

      config {
        image_path        = "/root/packer-windows/output-windowsserver/packer-windowsserver"

        # Use KVM acceleration
        accelerator       = "kvm"

        # Attempt a gracefull shutdown via power button emulation
        graceful_shutdown = true

        args = [
          "-nographic",
          "-device", "virtio-net-pci,netdev=net0",
          # Tell QEMU to listen on the allocated ssh port and forward connections
          "-netdev", "user,id=net0,hostfwd=tcp::${NOMAD_PORT_rdp}-:3389,hostfwd=tcp::${NOMAD_PORT_winrm}-:5986",
          # Supply the cloud-init metadata (NOMAD_ALLOC_DIR env variable does not work here)
          "-drive", "if=virtio,format=raw,file=/opt/nomad/data/alloc/${NOMAD_ALLOC_ID}/alloc/data/seed.img"
        ]

        port_map = {
          rdp = 3389
          winrm = 5986
        }
      }

      # We need to make sure the Windows VM actually has enough
      # resources to run the desktop environment after establishing
      # an RDP connection, otherwise the RDP connection chokes.
      resources {
        #cpu    = 5000 #Mhz
        memory = 4000 #Mb
        cores = 1
      }

      # Use an artifact to retrieve the image to run
#      artifact {
#        // http://mirror.softaculous.com/virtualizor/templates/windows-2019.img.gz
#        source = "./output-windowsserver/packer-windowsserver"
#        mode = "file"
#        destination = "local/packer-windowsserver.convert"
#      }
    }
  }
}
