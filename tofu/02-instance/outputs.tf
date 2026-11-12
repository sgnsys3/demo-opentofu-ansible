output "instances" {
  description = "hostname => IP"
  value = {
    for name, vm in var.instances : name => split("/", vm.ip_cidr)[0]
  }
}

output "ssh_commands" {
  value = [
    for name, vm in var.instances :
    "ssh -i ${abspath(pathexpand(var.ssh_private_key_path))} ${var.vm_user}@${split("/", vm.ip_cidr)[0]}"
  ]
}

output "ansible_inventory" {
  value = abspath(local_file.ansible_inventory.filename)
}
