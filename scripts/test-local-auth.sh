#!/usr/bin/env bash
# Exercises the real development generator against a disposable directory.
set -euo pipefail
project_root="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")/.." && pwd)"
fixture_root="$(mktemp -d)"
trap 'rm -rf -- "$fixture_root"' EXIT
prepare() {
  go -C "$project_root/database-broker" run ./scripts/prepare-dev-auth.go \
    --policy "$project_root/dev/broker-clients.yml" \
    --directory "$fixture_root/auth" --deployment-id razzie-cloud-development > /dev/null
}
prepare
[[ "$(stat -c %a "$fixture_root/auth")" == 700 ]]
[[ "$(stat -c %a "$fixture_root/auth/master")" == 600 ]]
[[ "$(stat -c %a "$fixture_root/auth/chess.token")" == 444 ]]
[[ -s "$fixture_root/auth/chess.token" ]]
cp "$fixture_root/auth/master" "$fixture_root/master.before"
cp "$fixture_root/auth/chess.token" "$fixture_root/chess.before"
prepare
cmp "$fixture_root/auth/master" "$fixture_root/master.before"
cmp "$fixture_root/auth/chess.token" "$fixture_root/chess.before"
printf 'Development auth fixtures passed (Chess token, private permissions, idempotent regeneration).\n'
