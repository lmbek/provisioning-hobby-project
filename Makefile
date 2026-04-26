APP_NAME=helloworld
TF_DIR=infra
DEPLOY_SCRIPT=deploy/deploy.sh
IP_FILE=secrets/ips
PASS_FILE=secrets/passwords
DEPLOYER_PASS_FILE=secrets/deployer_passwords
ENV_FILE=.env
SECRET_FILE=secrets/hcloud_token
HCLOUD_TOKEN=$(shell if [ -f $(SECRET_FILE) ]; then cat $(SECRET_FILE); fi)

# Path for project-specific SSH key
# We use a location that works even if the project is on a Windows mount (WSL)
SSH_KEY_DIR=$(HOME)/.ssh/first-time-provisioning
SSH_KEY=$(SSH_KEY_DIR)/id_ed25519
SSH_PUB_KEY=secrets/first-time-provisioning-ssh-key.public
SSH_PASSPHRASE_FILE=secrets/ssh_key_passphrase
SSH_CONFIG=secrets/ssh_config
SSH_KNOWN_HOSTS=secrets/known_hosts
SSH_PORT=22

# Load app configuration from .env
ifneq ("$(wildcard $(ENV_FILE))","")
    include $(ENV_FILE)
    export $(shell sed 's/=.*//' $(ENV_FILE))
endif

# Default server count if not provided in .env
SERVER_COUNT ?= 2

.PHONY: provision bootstrap setup infra deploy down keys ssh

provision:
	@$(MAKE) keys
	@$(MAKE) infra
	@$(MAKE) deploy

bootstrap: provision

keys:
	@mkdir -p $(SSH_KEY_DIR)
	@if [ ! -f $(SSH_KEY) ]; then \
		echo "🔑 Generating new SSH key pair with passphrase in $(SSH_KEY_DIR)..."; \
		PASSPHRASE=$$(openssl rand -base64 16 || head /dev/urandom | tr -dc A-Za-z0-9 | head -c 16); \
		echo "$$PASSPHRASE" > $(SSH_PASSPHRASE_FILE); \
		ssh-keygen -t ed25519 -f $(SSH_KEY) -N "$$PASSPHRASE" -q; \
	fi
	@cp $(SSH_KEY).pub $(SSH_PUB_KEY)
	@chmod 700 $(SSH_KEY_DIR)
	@chmod 600 $(SSH_KEY)
	@echo "🛠 Generating project-specific SSH config (Port $(SSH_PORT))..."
	@echo "Host *" > $(SSH_CONFIG)
	@echo "    Port $(SSH_PORT)" >> $(SSH_CONFIG)
	@echo "    IdentityFile $(SSH_KEY)" >> $(SSH_CONFIG)
	@echo "    UserKnownHostsFile $(SSH_KNOWN_HOSTS)" >> $(SSH_CONFIG)
	@echo "    IdentitiesOnly yes" >> $(SSH_CONFIG)
	@echo "    StrictHostKeyChecking accept-new" >> $(SSH_CONFIG)
	@echo "    ControlMaster auto" >> $(SSH_CONFIG)
	@echo "    ControlPath $(SSH_KEY_DIR)/cp-%r@%h:%p" >> $(SSH_CONFIG)
	@echo "    ControlPersist 10m" >> $(SSH_CONFIG)
	@echo "    ConnectTimeout 10" >> $(SSH_CONFIG)
	@touch $(SSH_KNOWN_HOSTS)
	@chmod 600 $(SSH_CONFIG) $(SSH_KNOWN_HOSTS) $(SSH_PASSPHRASE_FILE)

setup:
	@$(MAKE) -C scripts setup

infra:
	@if [ -z "$(HCLOUD_TOKEN)" ]; then \
		echo "❌ Error: HCLOUD_TOKEN is not set. Please add it to $(SECRET_FILE)."; \
		echo "You can get one at: https://console.hetzner.cloud/"; \
		exit 1; \
	fi
	@if ! command -v jq >/dev/null 2>&1; then \
		echo "❌ Error: 'jq' is not installed. It is required to process Terraform output."; \
		echo "Please run 'make setup' (if on WSL/Linux) or 'choco install jq' (if on Windows)."; \
		exit 1; \
	fi
	@if ! command -v nc >/dev/null 2>&1; then \
		echo "❌ Error: 'nc' (netcat) is not installed. It is required for deployment health checks."; \
		echo "Please run 'make setup' (if on WSL/Linux) or install it manually."; \
		exit 1; \
	fi
	@if ! command -v ssh-keygen >/dev/null 2>&1; then \
		echo "❌ Error: 'ssh-keygen' is not installed. It is required for managing host keys."; \
		exit 1; \
	fi
	@if ! command -v oathtool >/dev/null 2>&1; then \
		echo "❌ Error: 'oathtool' is not installed. It is required for 3-factor automation."; \
		echo "Please run 'make setup' or 'sudo apt install oathtool'."; \
		exit 1; \
	fi
	@if ! command -v expect >/dev/null 2>&1; then \
		echo "❌ Error: 'expect' is not installed. It is required for 3-factor automation."; \
		echo "Please run 'make setup' or 'sudo apt install expect'."; \
		exit 1; \
	fi
	@cd $(TF_DIR) && terraform init
	@cd $(TF_DIR) && terraform apply -auto-approve -var="hcloud_token=$(HCLOUD_TOKEN)" -var="server_count=$(SERVER_COUNT)"
	@cd $(TF_DIR) && terraform output -json ips | jq -r '.[]' > ../$(IP_FILE)
	@cd $(TF_DIR) && terraform output -json passwords | jq -r '.[]' > ../$(PASS_FILE)
	@cd $(TF_DIR) && terraform output -json deployer_passwords | jq -r '.[]' > ../$(DEPLOYER_PASS_FILE)
	@cd $(TF_DIR) && terraform output -json pam_tokens | jq -r '.[]' > ../secrets/pam_tokens
	@for ip in $$(cat $(IP_FILE)); do \
		ssh-keygen -f $(SSH_KNOWN_HOSTS) -R $$ip > /dev/null 2>&1; \
		ssh-keygen -f $(SSH_KNOWN_HOSTS) -R [$$ip]:$(SSH_PORT) > /dev/null 2>&1; \
	done
	@rm -f $(SSH_KNOWN_HOSTS).old

deploy:
	@APP_PORTS=$(APP_PORTS) SSH_KEY=$(SSH_KEY) SSH_PORT=$(SSH_PORT) bash $(DEPLOY_SCRIPT)

down:
	@cd $(TF_DIR) && terraform destroy -auto-approve -var="hcloud_token=$(HCLOUD_TOKEN)" -var="server_count=$(SERVER_COUNT)"
	@rm -f $(IP_FILE)
	@rm -f $(PASS_FILE)
	@rm -f $(DEPLOYER_PASS_FILE)
	@rm -f secrets/pam_tokens
	@rm -f $(SSH_PUB_KEY)
	@rm -f $(SSH_PASSPHRASE_FILE)
	@rm -f $(SSH_CONFIG)
	@rm -f $(SSH_KNOWN_HOSTS) $(SSH_KNOWN_HOSTS).old
	@rm -rf $(SSH_KEY_DIR)
	@rm -rf infra/state/

ssh:
	@$(MAKE) -C scripts ssh