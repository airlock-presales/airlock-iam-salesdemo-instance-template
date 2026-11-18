# Platform local - VM created manually (e.g. VMware Workstation)

OpenTofu does not create the VM; you create it and boot it from the Talos ISO. Phase 2 then installs Talos onto the VM's disk.

## Requirements

- Hypervisor on the workstation, e.g. VMware Workstation, with 4 vCPU, 8 GiB RAM and 50 GiB disk available
- Network on which the workstation reaches the VM, with
  - a fixed IP address for the VM (DHCP reservation)
  - a range of unused IP addresses in the same subnet for the gateway (LoadBalancer pool), **outside** the DHCP range

## Settings

```
platform = "local"
platform_local = {
  ip        = "192.168.145.145"                  # IP address of the VM
  # disk    = "/dev/sda"                         # system disk, default /dev/sda - NVMe: /dev/nvme0n1
  lb_pool   = "192.168.145.200-192.168.145.219"  # unused addresses, outside the DHCP range
  lb_subnet = "192.168.145.0/24"
}
```

## Steps

1. `make init`, then `make apply-1`: shows the output `iso_url` - download this ISO
2. Create the VM, e.g. in VMware Workstation:
   - guest OS: Linux, Other Linux 6.x kernel 64-bit
   - 4 vCPU, 8 GiB memory (2 vCPU make the initial installation very slow)
   - disk 1: 40 GiB, disk 2: 10 GiB - with a SCSI controller the system disk is `/dev/sda`; with NVMe (default for new VMs in recent versions) set `disk = "/dev/nvme0n1"`
   - network: NAT or bridged
   - CD/DVD: the downloaded Talos ISO
3. Fixed IP for the VM: DHCP reservation for the VM's MAC address
   - VMware NAT network (vmnet8), Linux host: `/etc/vmware/vmnet8/dhcpd/dhcpd.conf`, Windows host: `C:\ProgramData\VMware\vmnetdhcp.conf`, e.g.
     ```
     host salesdemo {
         hardware ethernet 00:0c:29:xx:xx:xx;
         fixed-address 192.168.145.145;
     }
     ```
     The default DHCP range of a VMware NAT network is `.128-.254`: reduce it (`range` in the same file), so that it does not overlap with `lb_pool`. Restart the VMware network services afterwards.
   - bridged: reservation in your router
4. Boot the VM: Talos starts in maintenance mode and shows its IP address on the console - it must match `ip`
5. `make apply-2` (Talos and Kubernetes, ~5 minutes) and `make apply-3` (ArgoCD), or `make build` for all phases
6. Name resolution on the workstation: `demo_fqdn` must resolve to the gateway's address (first address of `lb_pool`, see [usage](usage.md)), e.g. in `/etc/hosts`:
   ```
   192.168.145.200  demo.airlock.com
   ```

The VM can be suspended and resumed together with the laptop.
