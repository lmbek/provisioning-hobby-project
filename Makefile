APP_NAME=helloworld
TF_DIR=infra
DEPLOY_SCRIPT=deploy/deploy.sh
IP_FILE=secrets/ips
PASS_FILE=secrets/passwords
ENV_FILE=.env
SECRET_FILE=secrets/hcloud_token
HCLOUD_TOKEN=$(shell if [ -f $(SECRET_FILE) ]; then cat $(SECRET_FILE); fi)

# Path for project-specific SSH key
# We use a location that works even if the project is on a Windows mount (WSL)
SSH_KEY_DIR=$(HOME)/.ssh/first-time-provisioning
SSH_KEY=$(SSH_KEY_DIR)/id_ed25519
SSH_PUB_KEY=secrets/first-time-provisioning-ssh-key.public

# Load app configuration from .env
ifneq ("$(wildcard $(ENV_FILE))","")
    include $(ENV_FILE)
    export $(shell sed 's/=.*//' $(ENV_FILE))
endif

# Default server count if not provided in .env
SERVER_COUNT ?= 2

.PHONY: provisioning setup infra deploy down keys ssh

provisioning:
	@$(MAKE) keys
	@$(MAKE) infra
	@$(MAKE) deploy

keys:
	@mkdir -p $(SSH_KEY_DIR)
	@if [ ! -f $(SSH_KEY) ]; then \
		echo "🔑 Generating new SSH key pair in $(SSH_KEY_DIR)..."; \
		ssh-keygen -t ed25519 -f $(SSH_KEY) -N "" -q; \
	fi
	@cp $(SSH_KEY).pub $(SSH_PUB_KEY)
	@chmod 700 $(SSH_KEY_DIR)
	@chmod 600 $(SSH_KEY)

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
	@cd $(TF_DIR) && terraform init
	@cd $(TF_DIR) && terraform apply -auto-approve -var="hcloud_token=$(HCLOUD_TOKEN)" -var="server_count=$(SERVER_COUNT)"
	@cd $(TF_DIR) && terraform output -json ips | jq -r '.[]' > ../$(IP_FILE)
	@cd $(TF_DIR) && terraform output -json passwords | jq -r '.[]' > ../$(PASS_FILE)

deploy:
	@APP_PORTS=$(APP_PORTS) SSH_KEY=$(SSH_KEY) bash $(DEPLOY_SCRIPT)

down:
	@cd $(TF_DIR) && terraform destroy -auto-approve -var="hcloud_token=$(HCLOUD_TOKEN)" -var="server_count=$(SERVER_COUNT)"
	@rm -f $(IP_FILE)
	@rm -f $(PASS_FILE)
	@rm -f $(SSH_PUB_KEY)
	@rm -rf $(SSH_KEY_DIR)
	@rm -rf infra/state/

ssh:
	@$(MAKE) -C scripts ssh