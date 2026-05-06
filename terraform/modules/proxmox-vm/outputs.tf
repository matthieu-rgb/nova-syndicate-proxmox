output "vm_id" {
  description = "VMID Proxmox de la VM creee"
  value       = proxmox_virtual_environment_vm.vm.vm_id
}

output "hostname" {
  description = "Hostname de la VM"
  value       = proxmox_virtual_environment_vm.vm.name
}

output "ip_address" {
  description = "IP configuree sur la VM"
  value       = var.ip_address
}
