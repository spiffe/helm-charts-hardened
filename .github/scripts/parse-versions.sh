#!/usr/bin/env bash

TESTS_PATH="$(dirname "${BASH_SOURCE[0]}")/../tests"

# Set repo and version env variables
REPOS=$(jq -r '.[] | "export " + ("HELM_REPO_" + .name | ascii_upcase | gsub("-";"_")) + "=" + .repo' "${TESTS_PATH}/charts.json")
VERSIONS=$(jq -r '.[] | "export " + ("VERSION_" + .name | ascii_upcase | gsub("-";"_")) + "=" + .version' "${TESTS_PATH}/charts.json")
eval "$REPOS"
eval "$VERSIONS"
