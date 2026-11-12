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
  description = "Skip TLS certificate verification (self-signed certs)"
  type        = bool
  default     = true
}

# ---------- Placement ----------
variable "node_name" {
  description = "Proxmox node to build the template on"
  type        = string
  default     = "pve"
}

variable "image_datastore_id" {
  description = "Datastore for the cloud image (must allow content type 'import' - PVE 8.4+)"
  type        = string
  default     = "local"
}

variable "vm_datastore_id" {
  description = "Datastore for VM/template disks"
  type        = string
  default     = "local-lvm"
}

variable "bridge" {
  description = "Network bridge"
  type        = string
  default     = "vmbr0"
}

# ---------- Template ----------
variable "template_vm_id" {
  description = "VM ID of the template"
  type        = number
  default     = 9000
}

variable "template_name" {
  description = "Template name"
  type        = string
  default     = "ubuntu-2404-template"
}

variable "ubuntu_image_url" {
  description = "URL of the Ubuntu 24.04 (Noble) cloud image"
  type        = string
  default     = "https://cloud-images.ubuntu.com/noble/current/noble-server-cloudimg-amd64.img"
}

variable "disk_size" {
  description = "Template disk size (GB). The Ubuntu image is ~3.5 GB, so 5 GB is about the minimum. local-lvm is thin, so only written blocks use space."
  type        = number
  default     = 5
}
