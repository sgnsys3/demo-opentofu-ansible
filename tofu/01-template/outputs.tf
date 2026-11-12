output "template_vm_id" {
  description = "Template VM ID (used by 02-instance)"
  value       = proxmox_virtual_environment_vm.ubuntu_template.vm_id
}

output "template_name" {
  value = proxmox_virtual_environment_vm.ubuntu_template.name
}

output "template_node" {
  value = proxmox_virtual_environment_vm.ubuntu_template.node_name
}
