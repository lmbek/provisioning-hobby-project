APP_NAME=helloworld
TF_DIR=infra
DEPLOY_SCRIPT=deploy/deploy.sh
SETUP_SCRIPT=scripts/setup_local.sh
IP_FILE=.ip

# Path for project-specific SSH key
# We use a location that works even if the project is on a Windows mount (WSL)
SSH_KEY_DIR=$(HOME)/.ssh/first-time-provisioning
SSH_KEY=$(SSH_KEY_DIR)/id_ed25519
SSH_PUB_KEY=deploy/first-time-provisioning-ssh-key.public

# Load environment variables from .env
ifneq ("$(wildcard .env)","")
    include .env
    export $(shell sed 's/=.*//' .env)
endif

.PHONY: bootstrap setup infra deploy down keys

bootstrap:
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
	@chmod +x $(SETUP_SCRIPT)
	@$(SETUP_SCRIPT)

infra:
	@if [ -z "$(HCLOUD_TOKEN)" ]; then \
		echo "❌ Error: HCLOUD_TOKEN is not set. Please add it to your .env file."; \
		echo "You can get one at: https://console.hetzner.cloud/"; \
		exit 1; \
	fi
	cd $(TF_DIR) && terraform init
	cd $(TF_DIR) && terraform apply -auto-approve -var="hcloud_token=$(HCLOUD_TOKEN)"
	cd $(TF_DIR) && terraform output -raw ip > ../$(IP_FILE)

deploy:
	SSH_KEY=$(SSH_KEY) $(DEPLOY_SCRIPT)

down:
	cd $(TF_DIR) && terraform destroy -auto-approve -var="hcloud_token=$(HCLOUD_TOKEN)"
	rm -f $(IP_FILE)
	rm -f $(SSH_PUB_KEY)
	rm -rf $(SSH_KEY_DIR)