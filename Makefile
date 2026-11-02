.DEFAULT_GOAL := help
INFRA_ENV_FILE ?= $(CURDIR)/infra/.env

.PHONY: help latest-tags config deploy deploy-latest

help:
	@printf '%s\n' 'make latest-tags    Fetch stable service release tags and update infra/.env' 'make config         Validate and render the Swarm stack' 'make deploy         Deploy with the selected tags' 'make deploy-latest  Select the latest tags and deploy'

latest-tags:
	bash scripts/update-image-tags.sh "$(INFRA_ENV_FILE)"

config deploy:
	$(MAKE) -C infra ENV_FILE="$(abspath $(INFRA_ENV_FILE))" $@

deploy-latest: latest-tags
	$(MAKE) -C infra ENV_FILE="$(abspath $(INFRA_ENV_FILE))" deploy
