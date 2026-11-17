# Airlock IAM Salesdemo - instance

This repository defines one instance of the Airlock IAM Salesdemo: a single VM with Talos Linux and Kubernetes, on which ArgoCD deploys Airlock IAM, Airlock Microgateway and the tools around them. The installation itself comes from the base repository [airlock-iam-demo-base-wip](https://github.com/airlock-presales/airlock-iam-demo-base-wip) (documentation in its `docs/`); this repository only holds what is specific to your instance.

| File | Content |
|------|---------|
| `variables.auto.tfvars` | instance settings, encrypted with sops/age - empty in the template |
| `variables.template` | all settings with descriptions - template for `variables.auto.tfvars` |
| `release` | release of the base repository to deploy: git tag or branch (`main`) |
| `Makefile` | `make` targets, run `make` for a list |
| `.sops.yaml` | age public keys for the encryption |
| `iam/` | IAM configuration and server-side texts - created by `make init` from the base repository, then yours to change |
| `state/` | OpenTofu state, encrypted with `sec_state_passphrase` - created by `make build` |
| `backup/` | IAM database backup, encrypted with sops/age - created by `make backup` |

## Requirements

Tools on your workstation: see `docs/workstation.md` of the base repository; preparation of your platform: `docs/platform-<platform>.md`.

## Create your instance

1. Create your own (private) repository from this template and clone it.
2. Create an age key and keep it safe (e.g. password manager) - it is not committed. Without it, nothing in this repository can be decrypted.
   ```
   age-keygen -o age.keys
   age-keygen -y age.keys     # public key
   ```
   Put the public key into `.sops.yaml` (both rules). Several people sharing the instance: comma-separated list of their public keys.
3. Make the age key available to sops (in every shell you work in):
   ```
   export SOPS_AGE_KEY_FILE="${PWD}/age.keys"
   ```
4. Create the settings from the template, encrypted, then fill them in:
   ```
   cat variables.template | sops encrypt --filename-override variables.auto.tfvars > variables.auto.tfvars
   sops edit variables.auto.tfvars
   ```
   Fill in at least all keys marked `[required]`, keep the block of your platform and remove the other platform blocks; optional keys can be removed (defaults apply). The settings only exist encrypted in the repository; `make init` refuses to run if `variables.auto.tfvars` is not encrypted. Later changes: `sops edit variables.auto.tfvars`.
5. Initialise: checks out the base repository at `release` into `./salesdemo` (override with `SALESDEMO=<path>`), initialises OpenTofu and creates `iam/` (IAM configuration and server-side texts) from the template of the base repository
   ```
   make init
   ```
6. Commit and push.

## Deploy

```
export SOPS_AGE_KEY_FILE="${PWD}/age.keys"
make build              # phases 1-3, each asks for confirmation
```
or phase by phase with `make plan-<n>` / `make apply-<n>`, n = 1..3. Follow the platform documentation for the steps between the phases, if any. Then open `https://<demo_fqdn>/`.

**Commit `state/` after every change** - it is the only record of what was created.

## Daily use

| Task | Command |
|------|---------|
| change settings | `sops edit variables.auto.tfvars`, then `make apply-3` (or the phase concerned) |
| change the IAM configuration | edit `iam/iam-config.yaml` (or in the Config Editor, then `make iam-config-pull`), commit, `make apply-3` |
| back up the IAM database | `make backup` (`COMMIT=1` or `PUSH=1` to commit/push) |
| restore the IAM database | `make restore` |
| update to a newer release | `make backup`, change `release`, `make init`, `make build`; existing files in `iam/` are not replaced - merge changes of the new template (`salesdemo/iam/`) manually |
| remove the instance | `make remove` |

## Backup

The age key (kept outside the repository) and this repository, pushed with `state/`, `iam/` and `backup/`, are all that is needed to restore the instance: see `docs/backup.md` of the base repository. Never change or lose `sec_state_passphrase` and `sec_data_key`.
