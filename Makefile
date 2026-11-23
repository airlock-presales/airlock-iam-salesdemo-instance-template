# Airlock IAM Salesdemo - instance Makefile
#
# SALESDEMO  checkout of the salesdemo base repo, default ./salesdemo
# REPO       salesdemo base repo, cloned by 'make init' if SALESDEMO does not exist
# COMMIT     backup: commit the backup files (COMMIT=1)
# PUSH       backup: commit and push the backup files (PUSH=1)

SALESDEMO ?= ./salesdemo
REPO      ?= https://github.com/airlock-presales/airlock-iam-demo-base-wip
RELEASE   := $(shell tr -d '[:space:]' < release)
TOFUWRAP  := $(SALESDEMO)/bin/tofuwrap
IAMDB     := $(SALESDEMO)/bin/iamdb
IAMCONFIG := SALESDEMO=$(SALESDEMO) $(SALESDEMO)/bin/iamconfig
VMPOWER   := $(SALESDEMO)/bin/vmpower

all:
	@echo "Targets"
	@echo "  init         Check out salesdemo base repo at release '$(RELEASE)', initialise OpenTofu,"
	@echo "               create iam/iam-config.yaml from the template if missing"
	@echo "  build        Build Airlock IAM Salesdemo (all phases)"
	@echo "               Does not run unattended - you will need to confirm each phase"
	@echo "  remove       Remove Airlock IAM Salesdemo: destroy the VM (phase 1), drop the state of phases 2, 3"
	@echo "               Also removes leftovers of a lost instance; asks for confirmation"
	@echo "  plan-<n>     Show changes for phase n (1..3)"
	@echo "  apply-<n>    Apply changes for phase n (1..3); apply-3 then asks ArgoCD to refresh at once"
	@echo "  refresh      ArgoCD: render all applications now (instead of at the next reconciliation)"
	@echo "  stop         Azure: shut Talos down and deallocate the VM (no compute costs; disks, IPs kept)"
	@echo "  start        Azure: start the VM, wait until the Kubernetes node is ready"
	@echo "  backup       Back up the IAM database to backup/ (encrypted); COMMIT=1 or PUSH=1 to commit/push"
	@echo "  restore      Restore the IAM database from backup/ (IAM is stopped meanwhile)"
	@echo "  iam-config-pull  Copy the active IAM configuration (e.g. Config Editor changes) to iam/"
	@echo "  clean        Remove local OpenTofu working data (not the state)"

.PHONY: check
check:
	@test -n "$${SOPS_AGE_KEY_FILE}" || { echo "SOPS_AGE_KEY_FILE not defined - aborting"; exit 1; }

# settings must exist and be encrypted (sops) - an unencrypted file could be committed by mistake
.PHONY: check-settings
check-settings:
	@test -f variables.auto.tfvars || { echo "variables.auto.tfvars not found - create it with: sops edit variables.auto.tfvars (see README.md)"; exit 1; }
	@grep -q '"sops":' variables.auto.tfvars || { echo "variables.auto.tfvars is not encrypted - aborting. Encrypt it (sops encrypt --in-place --input-type binary --output-type binary variables.auto.tfvars) and make sure no unencrypted version was committed."; exit 1; }

.PHONY: checkout
checkout:
	test -d $(SALESDEMO) || git clone $(REPO) $(SALESDEMO)
	git -C $(SALESDEMO) fetch --tags origin
	git -C $(SALESDEMO) checkout $(RELEASE)
	git -C $(SALESDEMO) symbolic-ref -q HEAD >/dev/null && git -C $(SALESDEMO) pull --ff-only || true

.PHONY: init
init: check check-settings checkout
	$(IAMCONFIG) init
	$(TOFUWRAP) 1 init
	$(TOFUWRAP) 2 init
	$(TOFUWRAP) 3 init

.PHONY: build
build: check
	$(TOFUWRAP) 1 apply
	$(TOFUWRAP) 2 apply
	$(TOFUWRAP) 3 apply

# Only phase 1 creates resources outside the VM - phases 2 and 3 vanish with it, their state is
# dropped without destroy (works even if the cluster is unreachable). Resources already gone are
# removed from the phase 1 state, so 'remove' also cleans up leftovers of a lost instance.
# The phase 2/3 state is dropped only if the phase 1 destroy succeeded (not when declined).
.PHONY: remove
remove: check
	$(TOFUWRAP) 1 destroy
	rm -f state/02-talos.tfstate* state/03-argocd.tfstate*
	rm -rf output

plan-%: check
	$(TOFUWRAP) $* plan

apply-%: check
	$(TOFUWRAP) $* apply
	$(if $(filter 3,$*),@$(MAKE) --no-print-directory refresh)

# ArgoCD notices changed settings/configmaps only at its next reconciliation (120 s + jitter); a hard
# refresh renders all applications now (IAM then restarts within about a minute, once the repo server
# sees the new project settings)
.PHONY: refresh
refresh:
	@test -f output/kubeconfig.yaml || { echo "output/kubeconfig.yaml not found - phase 2 not applied?"; exit 1; }
	KUBECONFIG=output/kubeconfig.yaml kubectl -n argocd annotate applications --all argocd.argoproj.io/refresh=hard --overwrite

# Azure only: deallocate / start the VM (bin/vmpower; Azure CLI logged in)
.PHONY: stop
stop: check
	$(VMPOWER) stop

.PHONY: start
start: check
	$(VMPOWER) start

.PHONY: backup
backup: check
	$(IAMDB) backup $(if $(COMMIT),--commit) $(if $(PUSH),--push)

.PHONY: restore
restore: check
	$(IAMDB) restore

.PHONY: iam-config-pull
iam-config-pull: check
	$(IAMCONFIG) pull

.PHONY: clean
clean:
	rm -rf .tofu
