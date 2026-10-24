# kvm-lab: run `make` to see the targets.
SHELL := /bin/bash

# Secrets live in .env (git-ignored): PROXMOX_VE_API_TOKEN, OVIRT_ADMIN_PASSWORD
-include .env
export

TF := terraform -chdir=terraform
ANSIBLE := cd ansible && ansible-playbook
# Lab VMs keep their IPs but get a new SSH host key every time they're recreated.
# Their keys live in this file (not ~/.ssh/known_hosts), and `make up` forgets them.
KNOWN_HOSTS := ansible/.known_hosts

help: ## Show this help
	@grep -hE '^[a-z-]+:.*## ' $(MAKEFILE_LIST) | awk -F':.*## ' '{printf "  make %-10s %s\n", $$1, $$2}'

check: ## Check your local setup before the first run
	@command -v terraform >/dev/null || { echo "missing: terraform"; exit 1; }
	@command -v ansible-playbook >/dev/null || { echo "missing: ansible"; exit 1; }
	@command -v jq >/dev/null || { echo "missing: jq"; exit 1; }
	@test -f terraform/terraform.tfvars || { echo "missing: terraform/terraform.tfvars (copy terraform.tfvars.example)"; exit 1; }
	@test -n "$$PROXMOX_VE_API_TOKEN" || { echo "missing: PROXMOX_VE_API_TOKEN in .env (see .env.example)"; exit 1; }
	@echo "ok"

up: check ## Create/update the lab VMs enabled in terraform.tfvars
	$(TF) init -input=false -upgrade=false >/dev/null
	$(TF) apply
	@for ip in $$($(TF) output -json vms | jq -r '.[].ip // empty'); do \
	  ssh-keygen -R "$$ip" -f $(KNOWN_HOSTS) >/dev/null 2>&1 || true; \
	done

provision: ## Configure the lab VMs with Ansible
	$(ANSIBLE) site.yml

lab: up provision ## up + provision

ssh: ## SSH into a lab VM: make ssh VM=kvm
	@scripts/ssh.sh $(or $(VM),kvm)

ips: ## Show the lab VMs and their addresses
	@$(TF) output -json vms | jq -r 'to_entries[] | "\(.key)\t\(.value.vm_id)\t\(.value.name)\t\(.value.ip)"' | column -t

down: ## Destroy all lab VMs and the downloaded cloud images
	$(TF) destroy
	rm -f $(KNOWN_HOSTS) $(KNOWN_HOSTS).old

lint: ## Format/lint checks (terraform, shellcheck, ansible-lint if installed)
	$(TF) fmt -check -recursive
	$(TF) validate
	shellcheck -x scripts/*.sh labs/*/*.sh labs/lib/*.sh
	@if command -v ansible-lint >/dev/null; then cd ansible && ansible-lint site.yml; else echo "(ansible-lint not installed, skipped)"; fi

.PHONY: help check up provision lab ssh ips down lint
