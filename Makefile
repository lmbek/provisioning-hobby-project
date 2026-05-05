APP_NAME=helloworld
BIN_DIR=bin
TF_DIR=infra
IP_FILE=deploy/state/ips
PASS_FILE=deploy/state/passwords
DEPLOYER_PASS_FILE=deploy/state/deployer_passwords
ENV_FILE=.env
SECRET_FILE=secrets/hcloud_token
HCLOUD_TOKEN=$(shell if [ -f $(SECRET_FILE) ]; then cat $(SECRET_FILE); fi)

# Path for project-specific SSH key
# We use a location that works even if the project is on a Windows mount (WSL)
SSH_KEY_DIR=$(HOME)/.ssh/first-time-provisioning
SSH_KEY=$(SSH_KEY_DIR)/id_ed25519
SSH_PUB_KEY=deploy/state/first-time-provisioning-ssh-key.public
SSH_PASSPHRASE_FILE=deploy/state/ssh_key_passphrase
SSH_CONFIG=deploy/state/ssh_config
SSH_KNOWN_HOSTS=deploy/state/known_hosts
SSH_PORT=22
GO_CLI_BIN=$(CURDIR)/$(BIN_DIR)/go-cli

# Load app configuration from .env
ifneq ("$(wildcard $(ENV_FILE))","")
    include $(ENV_FILE)
    export $(shell sed 's/=.*//' $(ENV_FILE))
endif

# Default server count if not provided in .env
SERVER_COUNT ?= 2

.PHONY: provision bootstrap setup infra deploy sh_deploy ansible_deploy down keys ssh build-cli

build-cli: $(GO_CLI_BIN)

$(GO_CLI_BIN): deploy/go-cli/main.go deploy/go-cli/go.mod
	@mkdir -p $(BIN_DIR)
	@echo "🔨 Building Go CLI..."
	@cd deploy/go-cli && go build -o $(GO_CLI_BIN) .

provision:
	@$(MAKE) keys
	@$(MAKE) infra
	@$(MAKE) sh-deploy

bootstrap: provision

keys:
	@mkdir -p $(SSH_KEY_DIR)
	@mkdir -p deploy/ansible deploy/state $(BIN_DIR)
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
	@echo "Host *" > $(CURDIR)/$(SSH_CONFIG)
	@echo "    Port $(SSH_PORT)" >> $(CURDIR)/$(SSH_CONFIG)
	@echo "    IdentityFile $(SSH_KEY)" >> $(CURDIR)/$(SSH_CONFIG)
	@echo "    UserKnownHostsFile $(CURDIR)/$(SSH_KNOWN_HOSTS)" >> $(CURDIR)/$(SSH_CONFIG)
	@echo "    IdentitiesOnly yes" >> $(CURDIR)/$(SSH_CONFIG)
	@echo "    StrictHostKeyChecking accept-new" >> $(CURDIR)/$(SSH_CONFIG)
	@echo "    ControlMaster auto" >> $(CURDIR)/$(SSH_CONFIG)
	@echo "    ControlPath ~/.ssh/first-time-provisioning/cp-%r@%h:%p" >> $(CURDIR)/$(SSH_CONFIG)
	@echo "    ControlPersist 10m" >> $(CURDIR)/$(SSH_CONFIG)
	@echo "    ConnectTimeout 10" >> $(CURDIR)/$(SSH_CONFIG)
	@touch $(CURDIR)/$(SSH_KNOWN_HOSTS)
	@chmod 600 $(CURDIR)/$(SSH_CONFIG) $(CURDIR)/$(SSH_KNOWN_HOSTS) $(SSH_PASSPHRASE_FILE)

setup:
	@$(MAKE) -C scripts setup

infra:
	@mkdir -p deploy/ansible deploy/state
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
	@if ! command -v ansible-playbook >/dev/null 2>&1; then \
		echo "❌ Error: 'ansible-playbook' is not installed. It is required for deployment and maintenance."; \
		echo "Please run 'make setup' or 'sudo apt install ansible'."; \
		exit 1; \
	fi
	@cd $(TF_DIR) && terraform init
	@cd $(TF_DIR) && terraform apply -auto-approve -var="hcloud_token=$(HCLOUD_TOKEN)" -var="server_count=$(SERVER_COUNT)"
	@mkdir -p deploy/ansible deploy/state
	@cd $(TF_DIR) && terraform output -json ips | jq -r '.[]' > ../$(IP_FILE)
	@echo "[app]" > $(CURDIR)/deploy/ansible/inventory.ini
	@cd $(TF_DIR) && terraform output -json ips | jq -r '.[]' >> $(CURDIR)/deploy/ansible/inventory.ini
	@cd $(TF_DIR) && terraform output -json passwords | jq -r '.[]' > ../$(PASS_FILE)
	@cd $(TF_DIR) && terraform output -json deployer_passwords | jq -r '.[]' > ../$(DEPLOYER_PASS_FILE)
	@cd $(TF_DIR) && terraform output -json pam_tokens | jq -r '.[]' > ../deploy/state/pam_tokens
	@for ip in $$(cat $(IP_FILE)); do \
		ssh-keygen -f $(SSH_KNOWN_HOSTS) -R $$ip > /dev/null 2>&1; \
		ssh-keygen -f $(SSH_KNOWN_HOSTS) -R [$$ip]:$(SSH_PORT) > /dev/null 2>&1; \
	done
	@rm -f $(SSH_KNOWN_HOSTS).old

deploy: go-deploy


go-deploy:
	@echo "🔧 building app..."
	@mkdir -p $(BIN_DIR)
	@cd app && go mod tidy
	@cd app && CGO_ENABLED=0 GOOS=linux GOARCH=amd64 go build -o ../$(BIN_DIR)/$(APP_NAME) .
	@echo "🚀 deploying with Go CLI..."
	@$(MAKE) build-cli
	@SSH_KEY_PATH=$(SSH_KEY) $(GO_CLI_BIN) deploy

sh-deploy:
	@bash deploy/sh/deploy.sh

ansible-deploy:
	@echo "🔧 building app..."
	@mkdir -p $(BIN_DIR)
	@cd app && go mod tidy
	@cd app && CGO_ENABLED=0 GOOS=linux GOARCH=amd64 go build -o ../$(BIN_DIR)/$(APP_NAME) .
	@$(MAKE) -C scripts ansible_deploy

down:
	@cd $(TF_DIR) && terraform destroy -auto-approve -var="hcloud_token=$(HCLOUD_TOKEN)" -var="server_count=$(SERVER_COUNT)"
	@rm -f $(IP_FILE)
	@rm -f $(PASS_FILE)
	@rm -f $(DEPLOYER_PASS_FILE)
	@rm -f deploy/state/pam_tokens
	@rm -f $(SSH_PUB_KEY)
	@rm -f $(SSH_PASSPHRASE_FILE)
	@rm -f $(SSH_CONFIG)
	@rm -f deploy/ansible/inventory.ini
	@rm -f $(SSH_KNOWN_HOSTS) $(SSH_KNOWN_HOSTS).old
	@rm -rf $(SSH_KEY_DIR)
	@rm -rf infra/state/
	@rm -rf $(BIN_DIR)

ssh:
	@$(MAKE) -C scripts ssh