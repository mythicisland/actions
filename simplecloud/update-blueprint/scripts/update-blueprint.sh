#!/usr/bin/env bash
set -euo pipefail

echo "::add-mask::${NETWORK_CREDENTIAL}"

if [[ -z "${BLUEPRINT_ID}" && -z "${BLUEPRINT_NAME}" ]]; then
  echo "::error::Provide either blueprint-id or blueprint-name"
  exit 1
fi

API_URL="${API_URL%/}"

# Resolve blueprint-name to an id
if [[ -z "${BLUEPRINT_ID}" ]]; then
  LIST=$(curl -s -X GET "${API_URL}/v0/blueprints" \
    -H "X-Network-ID: ${NETWORK_ID}" \
    -H "X-Network-Credential: ${NETWORK_CREDENTIAL}")

  BLUEPRINT_ID=$(echo "${LIST}" | jq -r --arg name "${BLUEPRINT_NAME}" \
    '.blueprints[] | select(.name == $name) | .blueprint_id')

  if [[ -z "${BLUEPRINT_ID}" ]]; then
    echo "::error::No blueprint found with name '${BLUEPRINT_NAME}'"
    exit 1
  fi
fi

# Build payload with only the fields that were actually set
PAYLOAD=$(jq -n \
  --arg server_url "${IN_SERVER_URL}" \
  --arg name "${IN_NAME}" \
  --arg minecraft_version "${IN_MINECRAFT_VERSION}" \
  --arg server_software "${IN_SERVER_SOFTWARE}" \
  --arg software_version "${IN_SOFTWARE_VERSION}" \
  --arg configurator "${IN_CONFIGURATOR}" \
  --arg workflow_steps "${IN_WORKFLOW_STEPS}" \
  --arg runtime_type "${IN_RUNTIME_CONFIG_TYPE}" \
  --arg runtime_with "${IN_RUNTIME_CONFIG_WITH}" \
  '{server_url, name, minecraft_version, server_software, software_version, configurator}
   | with_entries(select(.value != ""))
   + (if $workflow_steps != "" then {workflow_steps: ($workflow_steps | split(",") | map(gsub("^\\s+|\\s+$";"")))} else {} end)
   + (if $runtime_type != "" or $runtime_with != "" then
        {runtime_config: (
          (if $runtime_type != "" then {type: $runtime_type} else {} end)
          + (if $runtime_with != "" then {with: ($runtime_with | fromjson)} else {} end)
        )}
      else {} end)')

if [[ "$(echo "${PAYLOAD}" | jq 'keys | length')" -eq 0 ]]; then
  echo "::error::No fields to update were provided"
  exit 1
fi

RESPONSE=$(curl -s -w "\n%{http_code}" \
  -X PATCH "${API_URL}/v0/blueprints?blueprint_id=${BLUEPRINT_ID}" \
  -H "Content-Type: application/json" \
  -H "X-Network-ID: ${NETWORK_ID}" \
  -H "X-Network-Credential: ${NETWORK_CREDENTIAL}" \
  -d "${PAYLOAD}")

HTTP_STATUS=$(echo "${RESPONSE}" | tail -n1)
BODY=$(echo "${RESPONSE}" | sed '$d')

if [[ "${HTTP_STATUS}" -ge 400 ]]; then
  echo "::error::Update failed (HTTP ${HTTP_STATUS}): ${BODY}"
  exit 1
fi

echo "${BODY}" | jq .

{
  echo "blueprint_id=${BLUEPRINT_ID}"
  echo "updated_at=$(echo "${BODY}" | jq -r '.updated_at // empty')"
  echo "response<<EOF"
  echo "${BODY}"
  echo "EOF"
} >> "${GITHUB_OUTPUT}"