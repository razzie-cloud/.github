#!/usr/bin/env bash
set -euo pipefail

project_root="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")/.." && pwd)"
env_file="${1:-$project_root/infra/.env}"
services=(database-broker access-gateway files)
keys=(DATABASE_BROKER_IMAGE_TAG ACCESS_GATEWAY_IMAGE_TAG FILES_IMAGE_TAG)
tags=()

latest_tag() {
  local repo="$1" refs latest tag ref
  refs="$(git -C "$repo" ls-remote --tags --refs origin)" || return
  latest="$(
    while IFS=$'\t' read -r _ ref; do
      tag="${ref#refs/tags/}"
      if [[ "$tag" =~ ^v?(0|[1-9][0-9]*)\.(0|[1-9][0-9]*)\.(0|[1-9][0-9]*)$ ]]; then
        printf '%s\t%s\n' "${tag#v}" "$tag"
      fi
    done <<< "$refs" | sort -t $'\t' -k1,1V -k2,2 | tail -n 1
  )" || return
  if [[ -z "$latest" ]]; then
    printf '%s: origin has no stable MAJOR.MINOR.PATCH tags\n' "$repo" >&2
    return 1
  fi
  printf '%s\n' "${latest#*$'\t'}"
}

# Resolve every service before fetching or changing the environment file.
for service in "${services[@]}"; do
  tags+=("$(latest_tag "$project_root/$service")")
done
for index in "${!services[@]}"; do
  git -C "$project_root/${services[index]}" fetch --no-recurse-submodules \
    origin tag "${tags[index]}"
done

dozzle_tag="$(awk -F= '$1 == "DOZZLE_IMAGE_TAG" { print $2; exit }' \
  "$project_root/infra/.env.example")"
if [[ -z "$dozzle_tag" ]]; then
  printf 'DOZZLE_IMAGE_TAG is missing from infra/.env.example\n' >&2
  exit 1
fi

source_file="$env_file"
if [[ ! -e "$source_file" ]]; then
  source_file="$project_root/infra/.env.example"
fi
mkdir -p -- "$(dirname -- "$env_file")"
temporary="$(mktemp "$env_file.tmp.XXXXXX")"
trap '[[ -z "$temporary" ]] || rm -f -- "$temporary"' EXIT

# Replace only service tag assignments, preserving operator settings and comments.
awk -v broker="${tags[0]}" -v gateway="${tags[1]}" -v files="${tags[2]}" \
  -v dozzle="$dozzle_tag" '
  BEGIN {
    split("DATABASE_BROKER_IMAGE_TAG ACCESS_GATEWAY_IMAGE_TAG FILES_IMAGE_TAG DOZZLE_IMAGE_TAG", keys, " ")
    tags[keys[1]] = broker
    tags[keys[2]] = gateway
    tags[keys[3]] = files
    tags[keys[4]] = dozzle
  }
  match($0, /^[[:space:]]*(export[[:space:]]+)?[A-Z_]+[[:space:]]*=/) {
    key = substr($0, 1, RLENGTH)
    sub(/^[[:space:]]*export[[:space:]]+/, "", key)
    gsub(/[[:space:]=]/, "", key)
    if (key in tags) {
      if (!seen[key]++) {
        if (key == "DOZZLE_IMAGE_TAG") print
        else print key "=" tags[key]
      }
      next
    }
  }
  { print }
  END {
    for (i = 1; i <= 4; i++)
      if (!seen[keys[i]]) print keys[i] "=" tags[keys[i]]
  }
' "$source_file" > "$temporary"
if [[ -e "$env_file" ]]; then
  chmod --reference="$env_file" "$temporary"
fi
mv -f -- "$temporary" "$env_file"
temporary=""

for index in "${!keys[@]}"; do
  printf '%s=%s\n' "${keys[index]}" "${tags[index]}"
done
printf 'Updated %s; check image publication before deploying.\n' "$env_file"
