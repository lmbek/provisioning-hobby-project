export ANSIBLE_CONFIG := $(CURDIR)/../deploy/ansible.cfg

.PHONY: setup ssh check-updates update-servers deploy open-tunnels

setup:
	@bash setup_local.sh

ssh: open-tunnels
	@bash ssh.sh

open-tunnels:
	@cd ../deploy && bash open_tunnels.sh

deploy: open-tunnels
	@cd ../deploy && ansible-playbook -i ansible/inventory.ini ansible/deploy.yml

check-updates: open-tunnels
	@cd ../deploy && ansible-playbook -i ansible/inventory.ini ansible/maintenance.yml -e action=check

update-servers: open-tunnels
	@cd ../deploy && ansible-playbook -i ansible/inventory.ini ansible/maintenance.yml -e action=upgrade
