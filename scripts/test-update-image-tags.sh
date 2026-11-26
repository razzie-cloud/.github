#!/usr/bin/env bash
# Offline tag-selection behavior; fake Git never contacts an operator remote.
set -euo pipefail
source_root="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")/.." && pwd)"
fixture_root="$(mktemp -d)"
trap 'rm -rf -- "$fixture_root"' EXIT
mkdir -p "$fixture_root"/{scripts,infra,bin,database-broker,access-gateway,files,notes,landing,chess,sudoku}
cp "$source_root/scripts/update-image-tags.sh" "$fixture_root/scripts/"
cat > "$fixture_root/infra/.env.example" <<'ENV'
DOMAIN=example.test
DOZZLE_IMAGE_TAG=example-default
ENV
cat > "$fixture_root/bin/git" <<'GIT'
#!/usr/bin/env bash
set -euo pipefail
printf '%s\n' "$*" >> "$TAG_FIXTURE_LOG"
service="${2##*/}"
case "$3" in
  ls-remote)
    [[ "$service" != "${TAG_FAIL_DISCOVERY:-}" ]] || exit 1
    if [[ "$service" == "${TAG_NO_STABLE:-}" ]]; then
      printf 'hash\trefs/tags/v2.0.0-rc1\nhash\trefs/tags/latest\n'
      exit 0
    fi
    printf 'hash\trefs/tags/v1.9.0\nhash\trefs/tags/v1.10.0\nhash\trefs/tags/v2.0.0-rc1\nhash\trefs/tags/v02.0.0\nhash\trefs/tags/latest\n'
    if [[ "$service" == chess ]]; then printf 'hash\trefs/tags/2.0.0\n'; fi
    ;;
  fetch) [[ "$service" != "${TAG_FAIL_FETCH:-}" ]] || exit 1 ;;
  *) exit 2 ;;
esac
GIT
chmod +x "$fixture_root/bin/git"
export PATH="$fixture_root/bin:$PATH"
export TAG_FIXTURE_LOG="$fixture_root/git.log"
selection="$fixture_root/infra/operator.env"
cat > "$selection" <<'ENV'
# preserve operator selections
DOMAIN=custom.test
DOZZLE_IMAGE_TAG=operator-choice
UUID_SERVER_IMAGE_TAG=keep-extra
FILES_IMAGE_TAG=old
export FILES_IMAGE_TAG=duplicate
CHESS_IMAGE_TAG=old
SUDOKU_IMAGE_TAG=old
ENV
chmod 0600 "$selection"
bash "$fixture_root/scripts/update-image-tags.sh" "$selection" > /dev/null
[[ "$(stat -c %a "$selection")" == 600 ]]
[[ "$(rg -c '^FILES_IMAGE_TAG=' "$selection")" == 1 ]]
rg -qx 'FILES_IMAGE_TAG=v1.10.0' "$selection"
rg -qx 'CHESS_IMAGE_TAG=2.0.0' "$selection"
rg -qx 'SUDOKU_IMAGE_TAG=v1.10.0' "$selection"
rg -qx 'DOZZLE_IMAGE_TAG=operator-choice' "$selection"
rg -qx 'UUID_SERVER_IMAGE_TAG=keep-extra' "$selection"
rg -qx 'DOMAIN=custom.test' "$selection"
[[ "$(rg -c 'ls-remote' "$TAG_FIXTURE_LOG")" == 7 ]]
[[ "$(rg -c 'fetch --no-recurse-submodules origin tag' "$TAG_FIXTURE_LOG")" == 7 ]]
if rg -q 'checkout|reset|razchess|uuid-server|geoip-server|0x40hues' "$TAG_FIXTURE_LOG"; then exit 1; fi
cp "$selection" "$fixture_root/expected.env"
export TAG_FAIL_DISCOVERY=sudoku
: > "$TAG_FIXTURE_LOG"
if bash "$fixture_root/scripts/update-image-tags.sh" "$selection" > /dev/null 2>&1; then exit 1; fi
cmp "$selection" "$fixture_root/expected.env"
if rg -q 'fetch' "$TAG_FIXTURE_LOG"; then exit 1; fi
unset TAG_FAIL_DISCOVERY
export TAG_NO_STABLE=chess
: > "$TAG_FIXTURE_LOG"
if bash "$fixture_root/scripts/update-image-tags.sh" "$selection" > /dev/null 2>&1; then exit 1; fi
cmp "$selection" "$fixture_root/expected.env"
if rg -q 'fetch' "$TAG_FIXTURE_LOG"; then exit 1; fi
unset TAG_NO_STABLE
export TAG_FAIL_FETCH=sudoku
if bash "$fixture_root/scripts/update-image-tags.sh" "$selection" > /dev/null 2>&1; then exit 1; fi
cmp "$selection" "$fixture_root/expected.env"
unset TAG_FAIL_FETCH
bash "$fixture_root/scripts/update-image-tags.sh" "$fixture_root/infra/new.env" > /dev/null
rg -qx 'DOZZLE_IMAGE_TAG=example-default' "$fixture_root/infra/new.env"
rg -qx 'CHESS_IMAGE_TAG=2.0.0' "$fixture_root/infra/new.env"
rg -qx 'SUDOKU_IMAGE_TAG=v1.10.0' "$fixture_root/infra/new.env"
printf 'Image-tag selection fixtures passed (seven services, atomic failures, preserved settings).\n'
