# First-time deployment cookbook

Use this cookbook to run Razzie Cloud's Swarm deployment commands from a new
workstation, WSL distribution, VM or development environment. It covers both an
existing stack and a brand-new installation.

Run commands from the **parent repository root** unless stated otherwise.
`infra/.env` configures deployment; the parent `.env` configures local Compose
and is separate. Substitute your context and stack names if you use different
values from the defaults `razcloud` and `razzie-cloud` in the examples.

## 1. Prepare the checkout and tools

You need Git with access to the service remotes, Bash, Make, GNU coreutils, Go
1.27, Docker CLI with Compose and `docker stack config`, and SSH access to the
Swarm manager. OpenSSL verifies recovered certificates below. Go builds the
deployment helper locally; applications run from published images.

```sh
git status
git submodule status
git submodule foreach 'git status --short --branch'
# After inspecting existing changes, initialize missing components:
git submodule update --init --recursive

go version
docker --version
docker compose version
docker stack config --help
```

Submodule initialization restores pinned commits, rather than selecting the
latest source or deployment images. The target must already be an active Swarm
manager. For a new server, complete [host preparation](../infra/nixos/README.md)
and Swarm initialization first. Point DNS for the domain and app subdomains at
the ingress manager and allow inbound 80/443. See
[infra prerequisites](../infra/README.md#first-deployment).

## 2. Create the Docker context in this environment

Contexts are local client configuration. A context on another machine or in
another user account is not automatically available here.

```sh
docker context ls
# Replace USER and SWARM_MANAGER with your SSH destination:
docker context create razcloud \
  --docker "host=ssh://USER@SWARM_MANAGER"

docker --context razcloud ps
docker --context razcloud info \
  --format 'state={{.Swarm.LocalNodeState}} manager={{.Swarm.ControlAvailable}}'
```

Expect `state=active manager=true`. Successful `ps` proves connectivity, but does
not establish that the endpoint is a manager. The SSH account needs access to
the remote Docker socket; see
[Docker's SSH connection documentation](https://docs.docker.com/engine/security/protect-access/#use-ssh-to-protect-the-docker-daemon-socket).

Reuse an existing context if it targets the right manager. There is no need to
switch the globally active context: the helper explicitly supplies `--context`
on every Docker command.

## 3. Select images and review the operator environment

```sh
# Initializes infra/.env from its example if absent; preserves operator settings:
make latest-tags
```

Review `infra/.env` in your editor. Confirm `DOCKER_CONTEXT`, `STACK_NAME`,
`DOMAIN`, broker settings and third-party image selections. Use simple `KEY=value`
assignments without shell quoting or secret values.

`latest-tags` selects stable Git releases for the broker, gateway, Files, Notes
and landing, retaining exact tag spelling. It does not prove image publication,
check out those releases, change parent submodule pins, or update the inactive
public apps' overrides. Swarm pulls published images rather than building this
checkout.

`make deploy-latest` combines selection and deployment. During initial setup,
use separate commands so you can review configuration first. After a preflight
failure, `make deploy` retries the existing selections without finding newer tags.

The parent supports `INFRA_ENV_FILE=/absolute/path/to/file`; standalone infra
uses `ENV_FILE`. Relative broker input paths resolve from `infra/`, where the
helper runs, even when the environment file lives elsewhere. Make command-line
assignments such as `DOCKER_CONTEXT=my-swarm` override the environment file.

## 4. Restore existing broker TLS inputs, or prepare new PKI

Token authentication is the default. Deployment needs a public policy, CA
certificate, server certificate and the name of a Swarm TLS private-key secret.
Git does not carry the ignored operator PKI files.

| Setting | Default | Required input |
| --- | --- | --- |
| `BROKER_CLIENTS_FILE` | `./broker-clients.yml` | Non-secret policy; preserve the deployed identity, key IDs and client generations |
| `BROKER_CA_FILE` | `./pki/broker-ca.pem` | Public CA certificate |
| `BROKER_TLS_CERT_FILE` | `./pki/broker.pem` | Public server certificate |
| `BROKER_TLS_KEY_SECRET` | `broker_tls_key` | Exact name of the existing or newly prepared Swarm secret |
| `BROKER_ORIGIN` | `https://database-broker:8443` | Private HTTPS origin matching the certificate hostname |

### Existing stack: recover public inputs without changing keys

A new operator machine does not require new production keys. Keep the TLS
secret, broker master and client tokens in Swarm. Obtain the original public
certificates and matching policy from another operator environment, or recover
the public data from the running stack's Docker configs.

Inspect references, without printing secret contents:

```sh
docker --context razcloud service inspect razzie-cloud_database-broker \
  --format '{{json .Spec.TaskTemplate.ContainerSpec.Configs}}'
docker --context razcloud service inspect razzie-cloud_database-broker \
  --format '{{json .Spec.TaskTemplate.ContainerSpec.Secrets}}'
docker --context razcloud service inspect razzie-cloud_files \
  --format '{{json .Spec.TaskTemplate.ContainerSpec.Configs}}'
```

Find the broker config mounted at `/run/configs/broker_cert.pem`, the Files config
mounted at `/run/configs/broker_ca.pem`, and the broker secret mounted as
`broker_tls_key`. Entries include the actual `ConfigID` or `SecretName`. Notes
also mounts the CA if Files is unavailable. The private-key secret may have a
dated or customized name; do not assume `broker_tls_key`.

Replace both placeholder IDs in this Bash recipe. Adapt the paths if your
environment file specifies other locations. Existing destination files are
protected from overwriting.

```bash
(
  set -euo pipefail
  set -o noclobber
  umask 077
  CA_CONFIG_ID=REPLACE_WITH_CA_CONFIG_ID
  CERT_CONFIG_ID=REPLACE_WITH_SERVER_CERT_CONFIG_ID
  mkdir -p infra/pki
  docker --context razcloud config inspect "$CA_CONFIG_ID" \
    --format '{{.Spec.Data}}' | base64 --decode > infra/pki/broker-ca.pem
  docker --context razcloud config inspect "$CERT_CONFIG_ID" \
    --format '{{.Spec.Data}}' | base64 --decode > infra/pki/broker.pem
)

openssl verify -CAfile infra/pki/broker-ca.pem \
  -verify_hostname database-broker infra/pki/broker.pem
openssl x509 -in infra/pki/broker.pem -noout -dates -ext subjectAltName
```

If an export fails, inspect any partial destination before removing it and
retrying. Stop if verification fails; confirm the config references, hostname,
certificate dates and local clock. For a customized `BROKER_ORIGIN`, verify its
hostname instead of `database-broker`.

Set `BROKER_TLS_KEY_SECRET` in `infra/.env` to the discovered `SecretName`.
Confirm that `BROKER_DEPLOYMENT_ID` and the local policy match the installation
you intend to maintain. The deployed policy is the config mounted at
`/run/configs/broker_policy.yml`; decode its `.Spec.Data` the same way into a
temporary file and compare it with `infra/broker-clients.yml`.

Only public inputs need recovery. The CA private key remains with its custodian
for renewal; broker masters, client tokens and the server private key remain in
Swarm. Keep certificates under ignored `infra/pki/` and settings in ignored
`infra/.env`. Do not run `make broker-pki` to replace an existing setup merely
because its local files are missing. See
[broker recovery and renewal](../infra/docs/broker-authentication.md).

### Brand-new installation: prepare PKI once

For a new installation without an existing broker TLS secret or certificate,
review the selected context and environment, then run:

```sh
make broker-pki
```

This changes the selected Swarm: it creates a TLS private-key secret and writes
local public certificates and a private CA key under ignored `infra/pki/`. The
server key is streamed directly to Swarm. Back up the CA private key securely
for renewal. Existing operator-issued PKI can supply these inputs instead.
Setup reuses matching inputs and refuses implicit rotation or incomplete
existing state. Normal deployment separately prepares the broker token master
and client tokens in Swarm.

## 5. Check GHCR access, including both adapter images

The stack needs two adapters in addition to the ordinary platform images:

- `ghcr.io/razzie-cloud/razchess-broker`
- `ghcr.io/razzie-cloud/geoip-server-broker`

Their default tags match `DATABASE_BROKER_IMAGE_TAG`. Explicit
`RAZCHESS_BROKER_IMAGE` and `GEOIP_SERVER_BROKER_IMAGE` settings override the full
references. Build and publish them before use; see
[adapter build instructions](../infra/docs/broker-authentication.md#images-and-tls).

Pull through the **target daemon**, replacing the placeholders with the selected
broker tag, including its `v` prefix when present:

```sh
docker --context razcloud image pull 'ghcr.io/razzie-cloud/database-broker:<selected-broker-tag>'
docker --context razcloud image pull 'ghcr.io/razzie-cloud/razchess-broker:<selected-broker-tag>'
docker --context razcloud image pull 'ghcr.io/razzie-cloud/geoip-server-broker:<selected-broker-tag>'
```

Pulling updates the manager's image cache but does not roll out services. A
successful public broker pull does not prove access to either adapter package.
Test the exact reference from your configuration when an override is present.

### Private packages: log in on this operator machine

```sh
docker login ghcr.io -u YOUR_GITHUB_USERNAME
```

At the password prompt, use a GitHub personal access token **classic** with
`read:packages`, from an account granted access to both packages. Authorize it
for organization SSO if required. Enter the token at the prompt rather than
putting it in a command, `.env` or this repository. Docker login in another user
account or on the remote server does not configure this local client's credentials.
See [GitHub's registry authentication instructions](https://docs.github.com/en/packages/working-with-a-github-packages-registry/working-with-the-container-registry#authenticating-with-a-personal-access-token-classic).

Retry the failing pulls. Deployment passes `--with-registry-auth` to supply local
registry authorization to Swarm nodes. `unauthorized` indicates an access
problem; after authentication, a missing tag may still require image publication.
Git release discovery cannot establish package access or image publication.

### Public packages: optional distribution choice

Public GHCR packages allow anonymous pulls. For each adapter, an administrator
can use **razzie-cloud → Packages → package → Package settings → Danger Zone →
Change visibility → Public**. GitHub states that a package made public cannot
be made private again. Repository access inheritance does not automatically
make the package public. See [GitHub's package visibility documentation](https://docs.github.com/en/packages/learn-github-packages/configuring-a-packages-access-control-and-visibility).

The [adapter Dockerfile](../infra/Dockerfile.broker-app) retains the upstream
application image and copies only `/broker-start` from the broker image. Its
recipe does not copy operator `.env`, PKI files or production tokens into the
image. Credentials and keys are supplied at runtime; making an image public
does not expose the running broker or grant access to its databases. Publishing
these adapters is reasonable alongside their open-source components, provided
published versions follow that recipe and contain no secrets. Review historical
versions and layers before changing visibility: a recipe review alone is not an
audit of every published artifact.

## 6. Validate, deploy and inspect the result

```sh
make config
# Review the target and selected releases before changing the running stack:
make deploy

docker --context razcloud stack services razzie-cloud
docker --context razcloud stack ps razzie-cloud --no-trunc
```

`make config` checks rendering, references and Swarm schema offline. It does
**not** prove manager connectivity, registry access, local certificate presence,
certificate validity or existence of referenced Swarm secrets. Deployment
performs these additional checks before preparing resources and rolling out.
The helper also waits for convergence and performs readiness/auth acceptance;
stop and investigate if a stage fails. Do not bypass it with a raw stack deploy.

For a brand-new stack, follow the [first-user bootstrap instructions](../infra/README.md#first-deployment)
to enroll the administrator. Existing installations retain accounts and secrets.
Verify the homepage, sign-in and protected apps at the configured domain.

## Troubleshooting the observed failures

The helper omits raw backend errors, so its top-level message may hide the
actionable cause. Run the smallest equivalent diagnostic directly. Avoid shell
tracing or dumping complete service environments, which can expose credentials.
Authentication is never automatically downgraded on failure.

| Deployment message or observation | What to check | Resolution |
| --- | --- | --- |
| `Docker operation failed: info --format` | `docker context ls`, then explicit-context `info` from step 2 | Create the missing context; check SSH/Docker permissions and confirm active manager status |
| `Operation failed; check public inputs and resource ownership` | Policy/certificate paths and readability; deployed config/secret references | This investigation found missing local public TLS files; recover them and select the existing TLS secret name. The generic message can also cover other file or decoding errors |
| `Docker operation failed: image pull` | Pull the configured image directly through the target daemon | This investigation found `unauthorized` on both adapters; configure local GHCR login or deliberately make the packages public. Check tag publication if authenticated pulls still fail |
| `make config` passes but deploy fails | Manager, PKI and registry checks above | Offline validation does not exercise these deployment prerequisites |
| Consumer rollout waits despite running, healthy tasks | Compare the affected service's task template with its running task, including `Placement.Platforms` | The original helper treated registry platform metadata differences as stale tasks. Use the corrected helper; increasing the timeout or restarting a healthy task is unnecessary for this mismatch |
| `Service update failed or rolled back: access-gateway` during consumer rollout | Service `UpdateStatus`, task history, failed task logs and database update timing | Fix the task's startup failure first. A transient database outage can leave a healthy replacement task but a paused rollout; use the recovery procedure below |

### Consumer rollout waits despite healthy tasks

In a subsequent attempt, all services had the requested running replicas and
containers with health checks were healthy, but the helper continued waiting.
Comparing the running tasks with their service templates isolated one difference:
Caddy's task retained an older `Placement.Platforms` list while the service had
an updated list. Its image digest and other task settings matched exactly.
Swarm does not necessarily replace a task for a placement-only change, as shown
by its [task comparison logic](https://github.com/moby/swarmkit/blob/master/manager/orchestrator/task.go).

The corrected local helper excludes registry-derived platform lists from the
comparison, while retaining checks for image digests, settings, secret/config
references and explicit placement constraints. It prints pending services and
ready-task counts when the wait state changes, and names pending services on
timeout. The previous helper silently polled until its convergence deadline.

`deploy.sh` builds its helper once at startup. An invocation already running
continues using the earlier binary. Interrupt that invocation with Ctrl+C and
allow its cleanup to finish before rerunning `make deploy` with the corrected
source. Completed service updates remain in effect; there is no automatic
rollback. A Caddy restart is not required for this metadata-only mismatch.

The `consumer rollout` stage also includes a separate readiness probe after
service convergence. Healthy container status alone does not mean this probe
has finished. It uses a temporary service named with a `-probe-` suffix and a
run identifier, then removes that service. Readiness retries, service scheduling,
SSH round trips and cleanup can take additional time without a new stage banner.
`DEPLOY_TIMEOUT` applies to individual waits rather than the whole deployment.
Inspect the current probe's task state before assuming another convergence bug:

```sh
docker --context razcloud service ls --format '{{.Name}} {{.Replicas}}'
# Replace PROBE_SERVICE_NAME with the currently listed temporary probe service:
docker --context razcloud service ps PROBE_SERVICE_NAME --no-trunc
```

A later retry reached this probe and completed successfully after waiting, as
reported by the operator. No further code change or service restart was needed
for that slower successful run.

### Consumer rollout paused after a transient startup failure

Inspect the affected service rather than inferring its status from the service
image or replica count alone:

```sh
docker --context razcloud service inspect razzie-cloud_access-gateway \
  --format '{{json .UpdateStatus}}'
docker --context razcloud service ps razzie-cloud_access-gateway --no-trunc
# Substitute the failed task ID from the task history:
docker --context razcloud service logs FAILED_TASK_ID --raw --timestamps --tail 50
docker --context razcloud service inspect razzie-cloud_postgres \
  --format '{{json .UpdateStatus}}'
docker --context razcloud service ps razzie-cloud_postgres --no-trunc
docker --context razcloud ps \
  --filter label=com.docker.swarm.service.name=razzie-cloud_access-gateway \
  --format '{{.ID}} {{.Status}} {{.Image}}'
```

Logs may contain credentials, including the first-user bootstrap token; inspect
them locally and redact before sharing. The container `ps` health check above
shows only containers on the manager reached by the context; inspect the task's
node separately in a multi-node installation.

In the observed failure, the gateway reported `error_kind=network` at stage
`migrate_postgres` while PostgreSQL was updating. Six seconds later, its
replacement applied the migration and started successfully. This points to a
temporary database interruption during concurrent service updates rather than
a migration SQL error. Swarm nevertheless paused the rolling update, leaving
one healthy old-version replica and one healthy new-version replica. A service's
desired image and `2/2` replica count do not prove that both replicas have upgraded.

Swarm ignores `depends_on`, and the helper's consumer stage currently deploys
the remaining stack together, including database services. Floating tags such
as `17-alpine` can resolve to a new digest even when their text is unchanged.
Plan database updates separately from application releases, and verify backend
readiness before resuming a rollout that failed during startup.

Once the underlying failure has cleared and the replacement task is healthy,
resume the paused update, then rerun the maintained deployment helper to complete
its convergence and acceptance checks:

```sh
# Changes the running service: resume its existing desired update.
docker --context razcloud service update --detach=false razzie-cloud_access-gateway
make deploy
```

Docker documents a plain `service update` as the way to resume a paused update;
`--force` is unnecessary here and would restart otherwise unchanged tasks.
See [paused update recovery](https://docs.docker.com/engine/swarm/swarm-tutorial/rolling-update/)
and [service update behavior](https://docs.docker.com/reference/cli/docker/service/update/).
If it pauses again, inspect the new failed task and stop retrying until that
cause is resolved. Resuming the update does not rotate credentials or change
the selected image. Do not automatically resume a rollback or suppress failure
checks to make the helper report success.

In the setup that prompted this cookbook, only the local `default` context
existed initially. After configuring the remote context, the checkout still
lacked the deployed broker's public CA/server certificates and used the example
TLS secret name rather than the installation's customized name. The certificates
were recovered from live Docker configs and verified for the broker hostname;
the local policy matched the deployed policy. Offline validation then passed.
Direct pulls succeeded for the broker, gateway, Files and Notes, while both
adapters rejected anonymous pulls. Those diagnostics updated local inputs and
the image cache without deploying or rotating production keys. The operator
subsequently reported a successful full deployment after the rollout fixes and
readiness wait described above. Package visibility changes were not independently
verified during the investigation.
