APP_NAME=helloworld
TF_DIR=infra
DEPLOY_SCRIPT=deploy/deploy.sh
IP_FILE=.ip

bootstrap:
	@$(MAKE) infra
	@$(MAKE) deploy

infra:
	cd $(TF_DIR) && terraform init
	cd $(TF_DIR) && terraform apply -auto-approve
	cd $(TF_DIR) && terraform output -raw ip > ../$(IP_FILE)

deploy:
	$(DEPLOY_SCRIPT)

down:
	cd $(TF_DIR) && terraform destroy -auto-approve
	rm -f $(IP_FILE)