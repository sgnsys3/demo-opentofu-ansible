# Clone VMs from the Ubuntu 24.04 template and configure them with cloud-init
resource "proxmox_virtual_environment_vm" "web" {
  for_each = var.instances

  name        = each.key
  description = "Ubuntu 24.04 web server - managed by OpenTofu"
  tags        = ["opentofu", "ubuntu-2404", "web"]

  node_name = var.node_name
  vm_id     = each.value.vm_id

  # Linked clone: the VM disk is a thin snapshot of the template disk,
  # so it only uses space for blocks that change. Needs the same storage as the template.
  clone {
    vm_id     = var.template_vm_id
    node_name = var.template_node_name
    full      = var.full_clone
  }

  started = true
  on_boot = true

  agent {
    enabled = false
  }

  cpu {
    cores = var.cores
    type  = "x86-64-v2-AES"
  }

  memory {
    dedicated = var.memory
  }

  # Keep the template's disk size (no extra space). Raise var.disk_size to grow it.
  disk {
    datastore_id = var.vm_datastore_id
    interface    = "scsi0"
    iothread     = true
    discard      = "on"
    ssd          = true
    size         = var.disk_size
  }

  network_device {
    bridge = var.bridge
    model  = "virtio"
  }

  initialization {
    datastore_id = var.vm_datastore_id
    # Put the cloud-init drive on SATA instead of the default ide2.
    # Some Ubuntu cloud images (e.g. 22.04) don't pick up an IDE cloud-init drive.
    interface = "sata0"

    dns {
      servers = var.dns_servers
    }

    ip_config {
      ipv4 {
        address = each.value.ip_cidr
        gateway = var.gateway
      }
    }

    user_account {
      username = var.vm_user
      keys     = [trimspace(file(pathexpand(var.ssh_public_key_path)))]
    }
  }
}

# Generate the Ansible inventory from OpenTofu data
resource "local_file" "ansible_inventory" {
  filename        = "${path.module}/../../ansible/inventory.ini"
  file_permission = "0644"

  content = templatefile("${path.module}/templates/inventory.tftpl", {
    hosts = {
      for name, vm in var.instances : name => split("/", vm.ip_cidr)[0]
    }
    user            = var.vm_user
    ssh_private_key = abspath(pathexpand(var.ssh_private_key_path))
  })

  depends_on = [proxmox_virtual_environment_vm.web]
}
