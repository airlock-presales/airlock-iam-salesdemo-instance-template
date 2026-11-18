# Platform kvm - VM on a KVM host via libvirt

OpenTofu creates the VM on the KVM host over ssh: disks from the Talos disk image (with qemu guest agent), VM definition, network interface.

## Requirements

- KVM host with libvirt, 4 vCPU, 8 GiB RAM and 50 GiB storage available (VM size: settings `vcpu`, `memory`)
- ssh access from the workstation to the KVM host with a key (no password prompt), as a user allowed to manage libvirt (`qemu:///system`, e.g. member of group `libvirt`)
- a libvirt storage pool for the disks (default `default`)
- a libvirt network (default `default`), e.g. a NAT network or a bridged network defined in libvirt, with
  - a fixed IP address for the VM: DHCP reservation for its MAC address - created by OpenTofu in a libvirt-managed network (NAT or routed, DHCP by libvirt); for a bridged network, configure it in the network's DHCP server (see Steps)
  - a range of unused IP addresses in the same subnet for the gateway (LoadBalancer pool), outside the DHCP range
- `zstd` on the workstation; the Talos disk image is downloaded to the workstation and uploaded to the KVM host

## Settings

```
platform = "kvm"
platform_kvm = {
  host      = "kvm.example.com"     # KVM host, as used for ssh
  user      = "admin"               # ssh user on the KVM host
  # pool    = "default"             # libvirt storage pool
  # network = "default"             # libvirt network
  ip        = "10.0.0.100"          # IP address of the VM
  mac       = "52:54:00:aa:bb:cc"   # MAC address of the VM, DHCP reservation for ip
  # dhcp_reservation = true         # false: bridged network, reservation in its DHCP server
  lb_pool   = "10.0.0.128/29"       # unused addresses: range a.b.c.d-a.b.c.e or CIDR
  lb_subnet = "10.0.0.0/24"
  # vcpu    = 4                     # VM size - 2 vCPU make the initial installation very slow
  # memory  = 8                     # GiB
}
```

## Steps

1. DHCP reservation for `mac` → `ip`:
   - **libvirt-managed network** (default, `dhcp_reservation = true`): nothing to do - phase 1 creates the reservation before the VM (`virsh net-update <network> add-last ip-dhcp-host …` over ssh) and removes it when the VM is destroyed. An existing reservation for the MAC is replaced.
   - **bridged network** (the VM is in the LAN, its DHCP server assigns the address): set `dhcp_reservation = false` and create the reservation in that DHCP server (router, dnsmasq, ISC/Kea DHCP, Windows DHCP …) for `mac` with `ip`, before `make build`. Without it, the VM gets another address and phase 2 waits in vain for the Talos node at `ip` (`talos_machine_configuration_apply` runs into its timeout).
2. `make init`, `make build`
3. Name resolution: `demo_fqdn` must resolve to the gateway's address (first address of `lb_pool`, see [usage](usage.md)) - DNS or `/etc/hosts`
