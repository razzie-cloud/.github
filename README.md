# razcloud

Parent repository for the razzie.cloud services and infrastructure. The three
components are independent Git repositories, tracked here as Git submodules at
specific commits.

| Directory | Repository | Purpose |
| --- | --- | --- |
| `access-gateway/` | [access-gateway](https://github.com/razzie-cloud/access-gateway) | Passkey accounts, expiring device registration links, and admin user management |
| `database-broker/` | [database-broker](https://github.com/razzie-cloud/database-broker) | Go API that provisions PostgreSQL databases and Dragonfly/Redis namespaces |
| `infra/` | [infra](https://github.com/razzie-cloud/infra) | Docker Swarm stack, deployment script, NixOS configuration, and Hanko image |

## Checkout

Clone this parent repository with `git clone --recurse-submodules <parent-url>`.
The parent URL is wherever this repository is eventually hosted. The submodules
use their existing GitHub SSH URLs, so cloning them requires GitHub SSH access.

For an existing checkout:

```sh
git submodule update --init --recursive
git submodule status
```

This checks out the commits recorded by the parent, usually with detached HEADs.
Before editing a component, switch to an appropriate branch within it. Preserve
any existing local work before switching branches or updating submodules.

## Development

Both services declare Go 1.27. Run Go commands from the individual service
directory; this parent has no Go module or workspace.

```sh
(cd access-gateway && go build ./... && go test ./...)
(cd database-broker && go build ./... && go test ./internal/config ./internal/broker ./internal/router ./internal/util)
```

The broker's full `go test ./...` suite also starts PostgreSQL and Dragonfly
containers through testcontainers and needs a reachable local Docker daemon.
See [AGENTS.md](AGENTS.md) for architecture, configuration, checks, and current
integration limitations. See [database-broker/README.md](database-broker/README.md)
for its API, [access-gateway/README.md](access-gateway/README.md)
for passkey setup, device onboarding, and admin user management, and
[infra/nixos/README.md](infra/nixos/README.md) for host setup.

## Updating components

Commit component changes in that component's repository, publish the commit to
its remote, then record the new pointer in the parent:

```sh
git -C database-broker status
# Commit and push the component changes using your development workflow.
git add database-broker
git commit -m "Update database-broker"
```

Use the same process for the other components. The parent records only their
commit IDs: uncommitted and untracked component files are not included. Publish
component commits before publishing parent commits that reference them.

Updating a parent pointer does not build or deploy a service. The Swarm stack
uses published images; image releases and stack image references must be updated
separately when a component change needs deployment.
