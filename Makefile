.DEFAULT_GOAL := help
INFRA_ENV_FILE ?= $(CURDIR)/infra/.env

.PHONY: help latest-tags config deploy deploy-latest broker-pki

help:
	@printf '%s\n' 'make latest-tags    Fetch stable service release tags and update infra/.env' 'make broker-pki     Prepare an internal broker CA and TLS secret' 'make config         Validate and render the Swarm stack' 'make deploy         Deploy with the selected tags' 'make deploy-latest  Select the latest tags and deploy'

latest-tags:
	bash scripts/update-image-tags.sh "$(INFRA_ENV_FILE)"

config deploy broker-pki:
	$(MAKE) -C infra ENV_FILE="$(abspath $(INFRA_ENV_FILE))" $@

deploy-latest: latest-tags
	$(MAKE) -C infra ENV_FILE="$(abspath $(INFRA_ENV_FILE))" deploy

.PHONY: local-auth
local-auth:
	python3 database-broker/scripts/prepare-dev-auth.py --policy dev/broker-clients.yml --directory .local/broker-auth --deployment-id razzie-cloud-development
