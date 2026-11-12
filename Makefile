SHELL := /bin/bash

# ---------- Local tooling ----------
# tofu is installed into ./bin, ansible into ./.venv (both are gitignored)
TOFU_VERSION ?= 1.13.9
OS     := $(shell uname -s | tr '[:upper:]' '[:lower:]')
ARCH   := $(shell uname -m | sed -e 's/x86_64/amd64/' -e 's/aarch64/arm64/')
PYTHON ?= python3

ROOT     := $(CURDIR)
TOFU     := $(ROOT)/bin/tofu
ANSIBLE  := $(ROOT)/.venv/bin/ansible
PLAYBOOK := $(ROOT)/.venv/bin/ansible-playbook

TOFU_ZIP := tofu_$(TOFU_VERSION)_$(OS)_$(ARCH).zip
TOFU_URL := https://github.com/opentofu/opentofu/releases/download/v$(TOFU_VERSION)
DL_DIR   := bin/.download

.PHONY: help setup venv tofu-install ssh-key versions clean-tools \
        template instance ping nginx all \
        destroy destroy-instance destroy-template

help:
	@echo "Setup:"
	@echo "  make setup             # install tofu (./bin) + ansible (./.venv)"
	@echo "  make tofu-install      # download OpenTofu v$(TOFU_VERSION) into ./bin"
	@echo "  make venv              # create .venv and install requirements.txt"
	@echo "  make ssh-key           # create a demo SSH key in ./.ssh (never touches ~/.ssh)"
	@echo "  make versions          # show tool versions"
	@echo "  make clean-tools       # remove ./bin and ./.venv"
	@echo ""
	@echo "Demo:"
	@echo "  make template          # 1-2) build the Ubuntu 24.04 template"
	@echo "  make instance          # 3)   clone VM(s) from the template + write inventory"
	@echo "  make ping              #      check Ansible can reach the VM(s)"
	@echo "  make nginx             # 4)   install nginx with Ansible"
	@echo "  make all               # run steps 1-4 in order"
	@echo "  make destroy           # destroy VM(s) and the template"

# ---------- Setup ----------
setup: tofu-install venv ssh-key versions

venv: .venv/.installed

.venv/.installed: requirements.txt
	$(PYTHON) -m venv .venv
	.venv/bin/pip install --upgrade pip
	.venv/bin/pip install -r requirements.txt
	@touch $@

# Project-local SSH key for the VMs. Make only creates it if it doesn't exist, so it is never replaced.
ssh-key: .ssh/id_ed25519

.ssh/id_ed25519:
	@mkdir -p .ssh && chmod 700 .ssh
	ssh-keygen -t ed25519 -N "" -C "opentofu-proxmox-demo" -f .ssh/id_ed25519

tofu-install: bin/tofu

bin/tofu:
	@mkdir -p $(DL_DIR)
	@echo "Downloading OpenTofu v$(TOFU_VERSION) ($(OS)/$(ARCH))..."
	curl -fsSL -o $(DL_DIR)/$(TOFU_ZIP) $(TOFU_URL)/$(TOFU_ZIP)
	curl -fsSL -o $(DL_DIR)/SHA256SUMS $(TOFU_URL)/tofu_$(TOFU_VERSION)_SHA256SUMS
	cd $(DL_DIR) && grep " $(TOFU_ZIP)$$" SHA256SUMS | sha256sum -c -
	unzip -o -q $(DL_DIR)/$(TOFU_ZIP) tofu -d bin
	chmod +x bin/tofu
	rm -f $(DL_DIR)/$(TOFU_ZIP) $(DL_DIR)/SHA256SUMS
	rmdir $(DL_DIR)
	@bin/tofu version | head -1

versions:
	@$(TOFU) version | head -1
	@$(ANSIBLE) --version | head -1

clean-tools:
	rm -rf ./bin ./.venv

# ---------- Demo ----------
template: bin/tofu
	cd tofu/01-template && $(TOFU) init -upgrade && $(TOFU) apply -auto-approve

instance: bin/tofu .ssh/id_ed25519
	cd tofu/02-instance && $(TOFU) init -upgrade && $(TOFU) apply -auto-approve

ping: venv
	cd ansible && $(ANSIBLE) all -m ping

nginx: venv
	cd ansible && $(PLAYBOOK) nginx.yml

all: template instance nginx

destroy-instance: bin/tofu .ssh/id_ed25519
	cd tofu/02-instance && $(TOFU) destroy -auto-approve

destroy-template: bin/tofu
	cd tofu/01-template && $(TOFU) destroy -auto-approve

destroy: destroy-instance destroy-template
