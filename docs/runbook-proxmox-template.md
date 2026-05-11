# Runbook: Proxmox Cloud-Init Template Maintenance (VMID 9000)

## Context

Template `debian-12-cloud-template-nova` (VMID 9000) is the base image for all nova-syndicate VMs.
Storage: `local-lvm` (LVM thin). No QEMU snapshots possible on LVM thin -- this is a known limitation.

---

## Creating a New Template from Scratch

```bash
# 1. Download Debian 12 cloud image on Proxmox host
ssh root@192.168.18.50
wget -O /tmp/debian-12-genericcloud-amd64.qcow2 \
  https://cloud.debian.org/images/cloud/bookworm/latest/debian-12-genericcloud-amd64.qcow2

# 2. Create VM
qm create 9000 --name debian-12-cloud-template-nova \
  --memory 2048 --cores 2 --net0 virtio,bridge=vmbr0 \
  --ostype l26 --serial0 socket --vga serial0 --agent enabled=1 \
  --scsihw virtio-scsi-single

# 3. Import disk
qm importdisk 9000 /tmp/debian-12-genericcloud-amd64.qcow2 local-lvm

# 4. Attach disk + cloud-init drive
qm set 9000 --scsi0 local-lvm:vm-9000-disk-0,size=3G --boot order=scsi0
qm set 9000 --ide2 local-lvm:cloudinit --ciuser debian

# 5. Set DNS explicitly (critical: prevents inheriting Proxmox host DNS)
qm set 9000 --nameserver "192.168.18.1" --searchdomain "nova-syndicate.local"

# 6. Boot, install qemu-guest-agent, clean cloud-init, shutdown
qm start 9000
# Wait for boot via console: qm terminal 9000
# Inside VM:
apt-get update && apt-get install -y qemu-guest-agent
systemctl enable qemu-guest-agent
cloud-init clean --logs --seed
truncate -s 0 /etc/machine-id
rm -f /var/lib/dbus/machine-id
shutdown -h now

# 7. Convert to template
qm set 9000 --template 1
lvchange -p r /dev/pve/base-9000-disk-0
```

---

## Maintaining an Existing Template

### Problem: Template needs updates (packages, config)

LVM thin base disks are read-only. Must temporarily make writable.

```bash
# Convert to regular VM
qm set 9000 --template 0
lvchange -p rw /dev/pve/base-9000-disk-0

# Start VM
qm start 9000

# Make changes via guest exec (no need to know IP)
qm guest exec 9000 -- bash -c "<your commands>"

# Or find IP and SSH
qm guest exec 9000 -- ip -4 addr show ens18

# Clean and shutdown
qm guest exec 9000 -- bash -c "
  cloud-init clean --logs --seed
  truncate -s 0 /etc/machine-id
  rm -f /var/lib/dbus/machine-id
  shutdown -h now
"

# Wait for stop
until [ "$(qm status 9000 | awk '{print $2}')" = "stopped" ]; do sleep 3; done

# Re-template
qm set 9000 --template 1
lvchange -p r /dev/pve/base-9000-disk-0
```

---

## Checklist Before Re-Templating

- [ ] Tailscale NOT installed: `dpkg -l tailscale` returns nothing
- [ ] No Tailscale data: `ls /var/lib/tailscale` fails
- [ ] DNS clean: `qm config 9000 | grep nameserver` shows `192.168.18.1` (not 100.100.100.100)
- [ ] cloud-init ISO clean: mount ISO and verify no `100.100.100.100` in network-config
- [ ] machine-id wiped: `/etc/machine-id` is empty
- [ ] cloud-init clean done: `/var/lib/cloud/` is empty or absent

### Verify cloud-init ISO

```bash
mkdir -p /tmp/ci9000
mount /dev/pve/vm-9000-cloudinit /tmp/ci9000
cat /tmp/ci9000/network-config
umount /tmp/ci9000
# Must show 192.168.18.1, NOT 100.100.100.100
```

---

## Testing After Template Update

```bash
# Clone to test VM
qm clone 9000 999 --name test-template-dns-check --full 1

# Start and verify
qm start 999
until qm guest exec 999 -- echo ready 2>/dev/null | grep -q ready; do sleep 5; done
qm guest exec 999 -- bash -c "cat /etc/resolv.conf"
# Must NOT contain 100.100.100.100

# Verify cloud-init ISO of clone
mkdir -p /tmp/ci999
mount /dev/pve/vm-999-cloudinit /tmp/ci999
cat /tmp/ci999/network-config
umount /tmp/ci999

# Destroy test clone
qm stop 999
until [ "$(qm status 999 | awk '{print $2}')" = "stopped" ]; do sleep 3; done
qm destroy 999 --purge
```

---

## Root Cause: Tailscale DNS Pollution (resolved 2026-05-11)

**Problem**: VMs cloned from VMID 9000 received `100.100.100.100` (Tailscale MagicDNS) and
`tail98861d.ts.net` as search domain, inherited from the Proxmox host's `/etc/resolv.conf`.

**Root cause**: Tailscale is installed on the Proxmox host (192.168.18.50). It overwrites
`/etc/resolv.conf`. When Proxmox generates cloud-init ISOs for VMs with no explicit DNS set,
it reads the host's `/etc/resolv.conf` and injects those DNS servers into the VM's
cloud-init `network-config`.

**Fix**: Set explicit DNS on VMID 9000 with `qm set 9000 --nameserver "192.168.18.1"
--searchdomain "nova-syndicate.local"`. This overrides host-level inheritance. Clones
inherit the explicit setting and never see Tailscale DNS.

**Note**: This setting must be set on every new template VM created on this Proxmox host,
as long as Tailscale remains installed on the host.

---

## Known Limitations

- LVM thin (`local-lvm`) does not support QEMU snapshots. No rollback possible.
  Backup strategy: clone to temp VM before major changes, destroy after validation.
- `qm snapshot` fails with "snapshot feature is not available" on LVM thin.
- Disk rename from `base-9000-disk-0` back to `vm-9000-disk-0` does NOT happen
  automatically when converting template to VM. The `lvchange -p rw` step is required.
