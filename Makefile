.DEFAULT_GOAL := help
INFRA_ENV_FILE ?= $(CURDIR)/infra/.env

.PHONY: help status push latest-tags config deploy deploy-latest broker-pki postgres-upgrade

help:
	@printf '%s\n' 'make status         Show subrepo branches, changed files and unpushed commits (local refs)' 'make push           Show status, then offer to push subrepo branches and all tags (Y/N)' 'make latest-tags    Fetch stable service release tags and update infra/.env' 'make broker-pki     Prepare an internal broker CA and TLS secret' 'make postgres-upgrade  Back up and upgrade PostgreSQL with Caddy offline' 'make config         Validate and render the Swarm stack' 'make deploy         Deploy with the selected tags' 'make deploy-latest  Select the latest tags and deploy'

status:
	@git submodule foreach --recursive '\
		git status --short --branch --untracked-files=all && \
		if upstream=$$(git rev-parse --verify --symbolic-full-name "@{upstream}" 2>/dev/null); then \
			printf "Unpushed commits relative to %s:\n" "$$upstream"; \
			git --no-pager log --oneline "$$upstream..HEAD"; \
		else \
			printf "No upstream; commits absent from all local remote-tracking refs:\n"; \
			git --no-pager log --oneline HEAD --not --remotes; \
		fi'

push: status
	@git submodule foreach --recursive '\
		branch=$$(git symbolic-ref --quiet --short HEAD) || { \
			printf "Detached HEAD in %s; switch to a branch before pushing.\n" "$$displaypath" >&2; exit 1; \
		}; \
		git rev-parse --verify "@{upstream}" >/dev/null 2>&1 || { \
			printf "No upstream for %s in %s; configure one before pushing.\n" "$$branch" "$$displaypath" >&2; exit 1; \
		}; \
		git for-each-ref --format="Push %(refname:short) to %(upstream:short), including all tags" "refs/heads/$$branch"'
	@printf 'Push current branches and ALL tags in initialized subrepos? [y/N] '; \
	if read -r answer && { [ "$$answer" = y ] || [ "$$answer" = Y ]; }; then \
		git submodule foreach --recursive '\
			branch=$$(git symbolic-ref --quiet --short HEAD) && \
			remote=$$(git config "branch.$$branch.remote") && \
			destination=$$(git config "branch.$$branch.merge") && \
			git push --tags "$$remote" "HEAD:$$destination"'; \
	else \
		printf 'Push cancelled.\n'; \
	fi

latest-tags:
	bash scripts/update-image-tags.sh "$(INFRA_ENV_FILE)"

config deploy broker-pki postgres-upgrade:
	$(MAKE) -C infra ENV_FILE="$(abspath $(INFRA_ENV_FILE))" $@

deploy-latest: latest-tags
	$(MAKE) -C infra ENV_FILE="$(abspath $(INFRA_ENV_FILE))" deploy

.PHONY: local-auth
local-auth:
	go -C database-broker run ./scripts/prepare-dev-auth.go --policy "$(CURDIR)/dev/broker-clients.yml" --directory "$(CURDIR)/.local/broker-auth" --deployment-id razzie-cloud-development
