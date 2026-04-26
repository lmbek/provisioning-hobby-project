export ANSIBLE_CONFIG := $(CURDIR)/../deploy/ansible/ansible.cfg

.PHONY: setup ssh check-updates update-servers ansible_deploy open-tunnels

setup:
	@bash setup_local.sh

ssh: open-tunnels
	@cd .. && $(MAKE) build-cli
	@cd .. && SSH_KEY_PATH=$(SSH_KEY) ./bin/go-cli ssh

open-tunnels:
	@cd .. && $(MAKE) build-cli
	@cd .. && SSH_KEY_PATH=$(SSH_KEY) ./bin/go-cli tunnels

ansible_deploy: open-tunnels
	@cd ../deploy && ansible-playbook -i ansible/inventory.ini ansible/ansible_deploy.yml

check-updates: open-tunnels
	@cd ../deploy && ansible-playbook -i ansible/inventory.ini ansible/maintenance.yml -e action=check

update-servers: open-tunnels
	@cd ../deploy && ansible-playbook -i ansible/inventory.ini ansible/maintenance.yml -e action=upgrade
