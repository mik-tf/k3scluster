# Default shell
SHELL := /bin/bash

# Colors for output
GREEN  := $(shell tput -Txterm setaf 2)
YELLOW := $(shell tput -Txterm setaf 3)
WHITE  := $(shell tput -Txterm setaf 7)
RESET  := $(shell tput -Txterm sgr0)

# Target Headers
TARGET_MAX_CHAR_NUM=20

## Show help
help:
	@echo ''
	@echo 'Usage:'
	@echo '  ${YELLOW}make${RESET} ${GREEN}<target>${RESET}'
	@echo ''
	@echo 'Targets:'
	@awk '/^[a-zA-Z\-\_0-9]+:/ { \
		helpMessage = match(lastLine, /^## (.*)/); \
		if (helpMessage) { \
			helpCommand = substr($$1, 0, index($$1, ":")-1); \
			helpMessage = substr(lastLine, RSTART + 3, RLENGTH); \
			printf "  ${YELLOW}%-$(TARGET_MAX_CHAR_NUM)s${RESET} ${GREEN}%s${RESET}\n", helpCommand, helpMessage; \
		} \
	} \
	{ lastLine = $$0 }' $(MAKEFILE_LIST)

## Deploy the K3s cluster
cluster:
	@echo "${GREEN}Deploying K3s cluster...${RESET}"
	@bash ./hacluster.sh

## Deploy the NGINX application
app-nginx:
	@echo "${GREEN}Deploying NGINX application...${RESET}"
	@bash ./app_nginx.sh

## Clean up the K3s cluster
clean-cluster:
	@echo "${GREEN}Cleaning up K3s cluster...${RESET}"
	@bash ./cleanup_hacluster.sh

## Clean up the NGINX application
clean-app:
	@echo "${GREEN}Cleaning up NGINX application...${RESET}"
	@bash ./cleanup_app.sh

.PHONY: help cluster app-nginx clean-cluster clean-app