# Workstation

Linux, macOS or Windows with WSL. Required tools:

| Tool | Version | Used for |
|------|---------|----------|
| [OpenTofu](https://opentofu.org/docs/intro/install/) | >= 1.9 | all phases |
| [sops](https://getsops.io/docs/#download) | >= 3.9 | decrypting instance settings |
| [age](https://github.com/FiloSottile/age) | | key for sops |
| git, make, bash, curl | | |
| zstd (`unzstd`) | | platform kvm: Talos disk image |
| xz, [Azure CLI](https://learn.microsoft.com/cli/azure/install-azure-cli) (`az`) | | platform azure |
| ssh | | platform kvm: libvirt connection |
| [talosctl](https://www.talos.dev/) | required | first configuration of the node (phase 2), `make stop`/`start` (Azure), administration and troubleshooting |
| kubectl | for `make backup`/`restore`, otherwise optional | IAM database backup, administration and troubleshooting |

## Installation examples (Linux)

- OpenTofu
  ```
  curl --proto '=https' --tlsv1.2 -fsSL https://get.opentofu.org/install-opentofu.sh -o install-opentofu.sh
  chmod +x install-opentofu.sh
  ./install-opentofu.sh --install-method standalone
  rm -f install-opentofu.sh
  ```
- sops
  ```
  SOPS_VERSION=3.13.3
  curl -LO https://github.com/getsops/sops/releases/download/v${SOPS_VERSION}/sops-v${SOPS_VERSION}.linux.amd64
  sudo install -m 755 sops-v${SOPS_VERSION}.linux.amd64 /usr/local/bin/sops
  rm sops-v${SOPS_VERSION}.linux.amd64
  ```
- age, zstd, xz
  - Debian/Ubuntu: `sudo apt-get install -y age zstd xz-utils`
  - Red Hat/Fedora: `sudo dnf install -y age zstd xz`
  - Suse: `sudo zypper install age zstd xz`
  - Gentoo: `sudo emerge app-crypt/age app-arch/zstd app-arch/xz-utils`
  - macOS: `brew install age zstd xz`

## Access to the repositories

- The base repository `airlock-iam-demo-base-wip` is private: `make init` clones it with your git credentials.
- ArgoCD in the cluster pulls from it too: put a GitHub token (read access to contents) into the instance settings `k8s_argocd_repo_username` / `k8s_argocd_repo_password`.
