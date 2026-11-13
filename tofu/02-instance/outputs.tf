output "instances" {
  description = "hostname => IP"
  value       = local.ips
}

output "ssh_commands" {
  value = [
    for name, ip in local.ips :
    "ssh -i ${abspath(pathexpand(var.ssh_private_key_path))} ${var.vm_user}@${ip}"
  ]
}

output "urls" {
  description = "Web pages to open after the Ansible playbooks have run"
  value = merge(
    { for name, ip in lookup(local.groups, "web", {}) : name => "http://${ip}/" },
    { for name, ip in lookup(local.groups, "monitoring", {}) : "${name} grafana" => "http://${ip}:3000/" },
    { for name, ip in lookup(local.groups, "monitoring", {}) : "${name} prometheus" => "http://${ip}:9090/" },
  )
}

output "ansible_inventory" {
  value = abspath(local_file.ansible_inventory.filename)
}
