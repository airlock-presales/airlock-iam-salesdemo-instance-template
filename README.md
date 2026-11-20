# Airlock IAM Salesdemo - instance

This repository defines one instance of the Airlock IAM Salesdemo: a single VM with Talos Linux and Kubernetes, on which ArgoCD deploys Airlock IAM, Airlock Microgateway and the tools around them. The installation itself comes from the base repository [airlock-iam-demo-base-wip](https://github.com/airlock-presales/airlock-iam-demo-base-wip), used like a library; this repository holds what is specific to your instance - and the documentation.

## Documentation

- [Workstation](docs/workstation.md) - tools required on the machine running the installation
- [Instance](docs/instance.md) - deploy, important notes, all settings
- Platforms - requirements and preparation: [local](docs/platform-local.md) (VM created manually, e.g. VMware Workstation), [kvm](docs/platform-kvm.md) (KVM host via libvirt), [azure](docs/platform-azure.md) (Microsoft Azure)
- [Usage](docs/usage.md) - accessing the demo, administration, IAM configuration, troubleshooting
- [Backup and restore](docs/backup.md) - what to back up, database backup, recovery of a lost instance
- How the installation works (architecture, phases, repository structure): [base repository](https://github.com/airlock-presales/airlock-iam-demo-base-wip/tree/main/docs)


| File | Content |
|------|---------|
| `variables.auto.tfvars` | instance settings, encrypted with sops/age - empty in the template |
| `variables.template` | all settings with descriptions - template for `variables.auto.tfvars` |
| `release` | release of the base repository to deploy: git tag or branch (`main`) |
| `Makefile` | `make` targets, run `make` for a list |
| `.sops.yaml` | age public keys for the encryption |
| `.gitattributes` | instance files kept on template updates (see [Keeping your instance up to date](#keeping-your-instance-up-to-date)) |
| `iam/` | IAM configuration and server-side texts - created by `make init` from the base repository, then yours to change |
| `state/` | OpenTofu state, encrypted with `sec_state_passphrase` - created by `make build` |
| `backup/` | IAM database backup, encrypted with sops/age - created by `make backup` |

## Requirements

Tools on your workstation: [docs/workstation.md](docs/workstation.md); preparation of your platform: `docs/platform-<platform>.md`.

## Create your instance

1. Create your own (private, empty) repository, e.g. on GitHub without README. Clone this template and push it there - the template stays connected as remote `template`, so you can merge its updates later (see [Keeping your instance up to date](#keeping-your-instance-up-to-date)):
   ```
   git clone https://github.com/airlock-presales/airlock-iam-salesdemo-instance-template.git my-instance
   cd my-instance
   git remote rename origin template
   git remote add origin <URL of your repository>
   git push -u origin main
   git config merge.ours.driver true
   ```
   Don't use GitHub's "Use this template" button: it creates a repository with a new, unrelated history, and merging template updates later becomes difficult.
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
| get updates of this template (docs, Makefile, settings template) | `git fetch template`, `git merge template/main`, see [below](#keeping-your-instance-up-to-date) |
| remove the instance | `make remove` |

## Keeping your instance up to date

Your repository shares its history with this template (remote `template`, see [Create your instance](#create-your-instance)). Get its updates by merging:

```
git fetch template
git log --oneline main..template/main     # what changed in the template
git merge template/main                   # resolve conflicts, if any
git push
```

- Files with instance content that also exist in the template - `variables.auto.tfvars`, `.sops.yaml`, `release` - keep your version when both sides changed them (`.gitattributes`, merge driver `ours`). The driver is a local git setting: run `git config merge.ours.driver true` once in every clone, otherwise such files show up as conflicts.
- Everything else (Makefile, docs, `variables.template`) comes from the template; if you changed one of these files too, git merges both or reports a conflict to resolve.
- After the merge, compare `variables.template` with your settings (`sops edit variables.auto.tfvars`) for new keys, and run `make init` if the Makefile changed.
- `iam/` is not part of the template: a newer base release brings a newer IAM configuration template (`salesdemo/iam/` after `make init`), which you merge into `iam/` manually (see "update to a newer release" above).

**Repository created with "Use this template", or older instances:** the histories are unrelated. Add the remote (`git remote add template https://github.com/airlock-presales/airlock-iam-salesdemo-instance-template.git`), set the merge driver, and merge once with `git merge --allow-unrelated-histories template/main` - resolve the conflicts (usually: keep your instance files, take the template's docs and Makefile). After that, updates merge normally.

## Backup

The age key (kept outside the repository) and this repository, pushed with `state/`, `iam/` and `backup/`, are all that is needed to restore the instance: see [docs/backup.md](docs/backup.md). Never change or lose `sec_state_passphrase` and `sec_data_key`.
