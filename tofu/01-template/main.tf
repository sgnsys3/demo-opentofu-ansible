# 1) Download the Ubuntu 24.04 LTS cloud image straight into Proxmox storage (via the API)
#    Content type "import" (PVE 8.4+) lets the disk be imported through the API - no SSH needed
#    Ubuntu's .img is already qcow2, so save it as .qcow2 which Proxmox expects
resource "proxmox_download_file" "ubuntu_noble" {
  node_name    = var.node_name
  datastore_id = var.image_datastore_id
  content_type = "import"
  url          = var.ubuntu_image_url
  file_name    = "noble-server-cloudimg-amd64.qcow2"

  upload_timeout = 1800
}

# 2) Create a VM from the cloud image and convert it into a template
resource "proxmox_virtual_environment_vm" "ubuntu_template" {
  name        = var.template_name
  description = "Ubuntu 24.04 LTS cloud-init template - managed by OpenTofu"
  tags        = ["opentofu", "template", "ubuntu-2404"]

  node_name = var.node_name
  vm_id     = var.template_vm_id

  template = true
  started  = false

  machine       = "q35"
  bios          = "seabios"
  scsi_hardware = "virtio-scsi-single"

  # The cloud image ships without qemu-guest-agent, so keep it off (we use static IPs instead)
  agent {
    enabled = false
  }

  cpu {
    cores = 2
    type  = "x86-64-v2-AES"
  }

  memory {
    dedicated = 2048
  }

  disk {
    datastore_id = var.vm_datastore_id
    import_from  = proxmox_download_file.ubuntu_noble.id
    interface    = "scsi0"
    iothread     = true
    discard      = "on"
    ssd          = true
    size         = var.disk_size
  }

  # cloud-init drive (real values are set on each clone)
  initialization {
    datastore_id = var.vm_datastore_id
    # Put the cloud-init drive on SATA instead of the default ide2.
    # Some Ubuntu cloud images (e.g. 22.04) don't pick up an IDE cloud-init drive.
    interface = "sata0"
    ip_config {
      ipv4 {
        address = "dhcp"
      }
    }
  }

  network_device {
    bridge = var.bridge
    model  = "virtio"
  }

  operating_system {
    type = "l26"
  }

  # Ubuntu cloud images expect a serial console
  serial_device {}

  vga {
    type = "serial0"
  }
}
