output "vm_id" {
  description = "VMID Proxmox de la VM OPNsense creee"
  value       = proxmox_virtual_environment_vm.opnsense.vm_id
}

output "hostname" {
  description = "Hostname de la VM OPNsense"
  value       = proxmox_virtual_environment_vm.opnsense.name
}
