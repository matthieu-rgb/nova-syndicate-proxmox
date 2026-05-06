output "vms_linux" {
  description = "IPs et VMIDs des VMs Linux deployees"
  value = {
    dc01         = { vmid = module.dc01.vm_id, ip = module.dc01.ip_address }
    fs01         = { vmid = module.fs01.vm_id, ip = module.fs01.ip_address }
    db01         = { vmid = module.db01.vm_id, ip = module.db01.ip_address }
    app01        = { vmid = module.app01.vm_id, ip = module.app01.ip_address }
    bastion01    = { vmid = module.bastion01.vm_id, ip = module.bastion01.ip_address }
    backup01     = { vmid = module.backup01.vm_id, ip = module.backup01.ip_address }
    web01        = { vmid = module.web01.vm_id, ip = module.web01.ip_address }
    mail01       = { vmid = module.mail01.vm_id, ip = module.mail01.ip_address }
    proxy_lyon01 = { vmid = module.proxy_lyon01.vm_id, ip = module.proxy_lyon01.ip_address }
    proxy_mrs01  = { vmid = module.proxy_mrs01.vm_id, ip = module.proxy_mrs01.ip_address }
  }
}

output "firewalls" {
  description = "VMIDs des firewalls OPNsense deployees"
  value = {
    wan_simulator = module.wan_simulator.vm_id
    fw_ext_lyon01 = module.fw_ext_lyon01.vm_id
    fw_int_lyon01 = module.fw_int_lyon01.vm_id
    fw_ext_mrs01  = module.fw_ext_mrs01.vm_id
  }
}
