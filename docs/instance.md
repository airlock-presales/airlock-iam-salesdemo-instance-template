# Instance

An instance is one deployment of the Airlock IAM Salesdemo, defined by its own (private) git repository - this one, created from the instance template. How the installation works internally: [base repository](https://github.com/airlock-presales/airlock-iam-demo-base-wip/tree/main/docs).

| File | Content |
|------|---------|
| `variables.auto.tfvars` | settings, encrypted with sops/age |
| `release` | release of the base repository to deploy: git tag (e.g. `v0.1.0`) or branch (`main`) |
| `Makefile` | targets `init`, `build`, `remove`, `plan-<n>`, `apply-<n>`, `backup`, `restore`, `iam-config-pull` |
| `.sops.yaml` | age public key(s) for encryption |
| `state/` | OpenTofu state, encrypted with `sec_state_passphrase` - commit it |
| `output/` | generated: kubeconfig, talosconfig - not committed |
| `iam/` | IAM configuration `iam-config.yaml` and server-side texts `<app>-texts/*.properties`, created from the template [iam/](https://github.com/airlock-presales/airlock-iam-demo-base-wip/tree/main/iam) by `make init` (existing files are never replaced) - commit it; see [usage](usage.md#iam-configuration) |
| `backup/` | IAM database backup, encrypted with sops/age (`make backup`) - commit it |

## Create an instance repository

See [README.md](../README.md): age key, `.sops.yaml`, settings (all keys with descriptions: `variables.template`), `make init`, commit. `make init` refuses to run if `variables.auto.tfvars` is not encrypted.

## Deploy

```
export SOPS_AGE_KEY_FILE="${PWD}/age.keys"
make init       # clone/check out the base repository at 'release' into ./salesdemo, initialise OpenTofu,
                # create the files of iam/ missing in the instance from the template - commit them
make build      # phases 1-3, each asks for confirmation
```

Then follow the platform documentation for the steps between phases, if any. Commit `state/` after every change.

`make remove` destroys the VM (phase 1) and drops the state of phases 2 and 3; it also removes leftovers of a lost instance, see [backup and restore](backup.md#recover-a-lost-instance).

## Backup

Back up the age key (outside the repository) and push the instance repository; `make backup` adds the IAM database to it. Restore, recovery of a lost instance and details: [backup and restore](backup.md).

## Important notes

### Passkeys need an official certificate

Browsers refuse passkeys (WebAuthn) on a site whose certificate they don't trust - even after the certificate warning was accepted. This affects passkey registration, passkeys as second factor and in particular the single-click login with a passkey from the username field. For demos with passkeys, use `tls_issuer = "letsencrypt"` or `"provided"` with a certificate from a CA the browsers trust. With `"internal"`, the cluster CA has to be imported on every client device - again after every reinstallation, which creates a new CA (see [usage](usage.md#certificate-of-the-internal-ca)).

### Creating partner administrators manually

Self-registering users name a responsible administrator by email address; the administrator activates them in the Adminapp. An administrator created manually (Adminapp) needs:
- an email address (context data `email`) - matched with the address entered at the self-registration,
- a value for company (context data `company`) - self-registered users of this administrator are assigned to realm `users-<company>` (in realm names, spaces become `-`, other characters than letters, digits, `-`, `_` become `_`, max. 44 characters; e.g. `Big Oil & Gas AG` → `users-Big-Oil-_-Gas-AG`),
- realm `demo-admins`,
- role `partner-admin` (found as responsible administrator; portal entries Adminapp and Mailpit),
- realm role `adm-<company>` (company normalized as above) - with a delegation to realm `users-<company>` (user management permissions), created by an administrator with `superadmin` or `realmadmin` in the Adminapp (*Realm Management*) if it doesn't exist yet.

## Settings reference

Required settings are marked *.

| Setting | Description |
|---------|-------------|
| `demo_name` * | instance name: lowercase letters, digits, '-'; used for VM, cluster and cloud resource names |
| `demo_fqdn` * | host name of the demo, e.g. `demo.airlock.com` |
| `sec_state_passphrase` * | passphrase for state encryption, min. 16 characters, e.g. `openssl rand -base64 32` |
| `sec_password_argocd` | ArgoCD admin password; empty: generated, see [usage](usage.md) |
| `sec_data_key` * | secret from which the keys protecting persistent data are derived (Airlock 2FA storage encryption and OATH OTP secrets in the database, new-device cookie), min. 32 characters, e.g. `openssl rand -base64 48`; never change it - with the same value, a reinstallation gets the same keys and a database backup stays readable |
| `sec_password_iam` * | initial password of the IAM administrators `emergency` (emergency administrator in `medusa_admin`) and `admin` (realm administrator in `medusa_user`); used only when they are created |
| `tls_issuer` | `internal` (default): certificate from the cluster CA; `letsencrypt`: requires public DNS and port 80 reachable from the internet; `provided`: certificate and key from the settings below |
| `tls_acme_email` | optional e-mail for Let's Encrypt |
| `tls_certificate` | `tls_issuer = "provided"`: certificate for `demo_fqdn` followed by the intermediate chain (PEM, heredoc); checked for expiry (error if expired, warning 30 days before), not for the DNS names |
| `tls_private_key` | `tls_issuer = "provided"`: its private key (PEM, heredoc) |
| `vm_timezone` | default `Europe/Zurich` |
| `vm_admin_ips` | IP addresses or CIDR ranges allowed to access the Talos and Kubernetes API and the Adminapp of the local administrator (port 8443); required on cloud platforms; empty: no restriction on port 8443 |
| `vm_ntp_servers` | default `pool.ntp.org`, `time.cloudflare.com` |
| `platform` * | `local`, `kvm`, `azure` |
| `platform_<platform>` * | settings of the selected platform, see platform documentation |
| `k8s_argocd_repo_url` * | base repository for ArgoCD, e.g. `https://github.com/airlock-presales/airlock-iam-demo-base-wip` |
| `k8s_argocd_repo_username`, `k8s_argocd_repo_password` | credentials for https, e.g. GitHub user and token |
| `k8s_argocd_repo_ssh_key` | private key for ssh repository URLs |
| `k8s_ghcr_pull` | credentials to pull the salesdemo images (argocd-cli, qr-service) from ghcr.io, as long as the packages are not public: `{ username = "...", token = "..." }` (classic PAT with scope `read:packages`; SSO-authorized for airlock-presales) |
| `airlock_iam_license`, `airlock_mgw_license` | Airlock licenses (heredoc `<<EOT ... EOT` for multiple lines) |
| `airlock_iam_pull_username`, `airlock_iam_pull_password` | credentials to pull the Airlock IAM image from quay.io |
| `airlock_iam_config_sync` | copy the deployed IAM configuration into the instance: `changed` (default, when the deployed configuration changed), `always` (on every IAM start), `never` (e.g. while working in the Config Editor); see [usage](usage.md#iam-configuration) |
| `airlock_iam_config_restore_users` | users allowed to restore the deployed IAM configuration from the portal (entry *Restore IAM configuration*; they also need role `superadmin` or `demo-admin` and a second factor); empty (default): all such administrators |
| `airlock_iam_admin_oidc` | optional OIDC client at an external OIDC provider (e.g. secure.ergon.ch) for an administrator login added to the IAM configuration: `{ client_id = "...", client_secret = "..." }`; not used by the configuration template, see [usage](usage.md#administrator-access) |
| `airlock_iam_futurae` * | Futurae service for Airlock 2FA: `{ service_id = "...", auth_api_key = "...", admin_api_key = "..." }` |
| `airlock_iam_pxl` * | PXL Vision identity proofing (test environment): `{ api_key = "...", account_id = "..." }` |
| `airlock_iam_smtp` | SMTP server for emails sent by IAM: `{ host = "...", port = 587, tls = "starttls", username = "...", password = "...", sender = "iam@example.com" }` (`tls`: `none`, `starttls`, `ssl`; `port` and `tls` optional); not set: emails are caught by Mailpit |

Everything else (versions, sizes, components) is defined by the release of the base repository.
