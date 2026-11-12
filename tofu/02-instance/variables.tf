# ---------- Proxmox connection ----------
variable "proxmox_endpoint" {
  description = "Proxmox API URL, e.g. https://192.168.1.10:8006/"
  type        = string
}

variable "proxmox_api_token" {
  description = "API token in the form USER@REALM!TOKENID=SECRET"
  type        = string
  sensitive   = true
}

variable "proxmox_insecure" {
  type    = bool
  default = true
}

# ---------- Placement ----------
variable "node_name" {
  description = "Proxmox node to create the VMs on"
  type        = string
  default     = "pve"
}

variable "vm_datastore_id" {
  type    = string
  default = "local-lvm"
}

variable "bridge" {
  type    = string
  default = "vmbr0"
}

# ---------- Template (from 01-template) ----------
variable "template_vm_id" {
  description = "VM ID of the template built by 01-template"
  type        = number
  default     = 9000
}

variable "template_node_name" {
  description = "Node where the template lives"
  type        = string
  default     = "pve"
}

# ---------- Instances ----------
variable "instances" {
  description = "VMs to create: key = hostname"
  type = map(object({
    vm_id   = number
    ip_cidr = string # e.g. 192.168.1.101/24
  }))
  default = {
    "web-01" = { vm_id = 201, ip_cidr = "192.168.1.101/24" }
  }
}

variable "gateway" {
  type    = string
  default = "192.168.1.1"
}

variable "dns_servers" {
  type    = list(string)
  default = ["1.1.1.1", "8.8.8.8"]
}

variable "full_clone" {
  description = "true = full copy of the template disk, false = linked clone (saves space; the template can't be deleted while clones exist)"
  type        = bool
  default     = false
}

variable "cores" {
  type    = number
  default = 2
}

variable "memory" {
  description = "RAM (MB)"
  type        = number
  default     = 2048
}

variable "disk_size" {
  description = "Disk size (GB) - must be >= the template disk size (5 GB). Keep it equal to avoid using extra space."
  type        = number
  default     = 5
}

# ---------- Access ----------
variable "vm_user" {
  description = "User created by cloud-init (passwordless sudo)"
  type        = string
  default     = "ubuntu"
}

# Default: the project-local key created by `make ssh-key` (paths are relative to tofu/02-instance)
variable "ssh_public_key_path" {
  description = "SSH public key injected by cloud-init"
  type        = string
  default     = "../../.ssh/id_ed25519.pub"
}

variable "ssh_private_key_path" {
  description = "Written into the Ansible inventory (as an absolute path)"
  type        = string
  default     = "../../.ssh/id_ed25519"
}
