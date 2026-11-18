# Platform azure - Microsoft Azure

OpenTofu creates everything in a new resource group `salesdemo-<demo_name>`: network, security group, two public IPs, storage account with the Talos image, VM (`Standard_D4s_v5`, setting `vm_size`) with system and data disk.

## Requirements

- Azure subscription; your account needs permission to create resource groups and resources, e.g. role *Contributor* on the subscription
- vCPU quota for the DSv5 family in the chosen region (4 vCPU)
- Azure CLI (`az`) and `xz` on the workstation, logged in:
  ```
  az login
  az account set --subscription <subscription id>
  ```
- A DNS zone in which you can create an A record for `demo_fqdn`
- Your public IP address(es) for `vm_admin_ips`, e.g. `curl -4 ifconfig.me`

## Network

| Public IP | Ports | Access | Purpose |
|-----------|-------|--------|---------|
| admin (output `endpoint_ip`) | 50000, 6443 | `vm_admin_ips` only | Talos API, Kubernetes API |
| demo (output `lb_public_ip`) | 80, 443 | everyone | Airlock Microgateway: demo, ArgoCD, Adminer, Headlamp, Mailpit |
| demo (output `lb_public_ip`) | 8443 | `vm_admin_ips` | Airlock Microgateway: Adminapp for the local administrator |

## Settings

```
platform = "azure"
platform_azure = {
  subscription_id = "00000000-0000-0000-0000-000000000000"
  location        = "switzerlandnorth"
  # vm_size       = "Standard_D4s_v5" # 4 vCPU, 16 GiB - D2s_v5 (2 vCPU) makes the initial installation very slow
}
vm_admin_ips = ["203.0.113.10/32"]
tls_issuer   = "letsencrypt"      # once DNS is in place, see below
```

## Steps

1. `make init`, `make apply-1`: creates the resources (~10 minutes, mostly the image upload); note the output `lb_public_ip`
2. DNS: A record `demo_fqdn` → `lb_public_ip`
3. `make apply-2`, `make apply-3`
4. Let's Encrypt is used if `tls_issuer = "letsencrypt"`; the record from step 2 must resolve publicly before the gateway certificate is requested.
   With `internal`, the certificate is issued by the cluster CA (browser warning).

## Costs

The VM, two Premium SSD disks (40 + 10 GiB) and two static public IPs are billed while they exist. To save costs when the demo is not needed, deallocate the VM (disks and IPs are still billed):
```
az vm deallocate -g salesdemo-<demo_name> -n <demo_name>-controlplane-0
az vm start      -g salesdemo-<demo_name> -n <demo_name>-controlplane-0
```
`make remove` deletes everything.
