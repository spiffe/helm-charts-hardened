#!/usr/bin/env bash

# Verify that the shields.io version badges in each top-level chart README
# agree with the version and appVersion declared in the sibling Chart.yaml.
# Nothing regenerates those badges, so they drift silently as charts are bumped.
#
# READMEs without a Version badge (library charts, hand written docs) are
# skipped. A leading 'v' is ignored when comparing, so 'v0.3.0' matches '0.3.0'.

set -euo pipefail

SCRIPT="$(readlink -f "$0")"
SCRIPTPATH="$(dirname "${SCRIPT}")"
REPO_ROOT="$(dirname "${SCRIPTPATH}")/.."

function print_problem {
  echo >&2 "  ❌ ${*}"
}

function require_command {
  command -v "$1" >/dev/null 2>&1 || {
    print_problem "$2"
    exit 1
  }
}

# Print the value of a shields.io badge as "<alt text> <url value>", or nothing
# at all when the badge is absent. Each version is spelled twice in the badge
# markup, and both spellings need checking.
function badge_values {
  local readme="$1"
  local name="$2"
  local badge alt url

  badge="$(grep -o "!\[${name}: [^]]*\](https://img.shields.io/badge/${name}-[^)]*)" "${readme}" | head -1 || true)"
  if [ -z "${badge}" ]; then
    return 0
  fi

  alt="$(printf '%s' "${badge}" | sed "s#^!\[${name}: \([^]]*\)\].*#\1#")"
  # shields.io escapes a literal dash in the value as '--'
  url="$(printf '%s' "${badge}" | sed "s#.*/badge/${name}-\(.*\)-informational.*#\1#; s#--#-#g")"

  printf '%s %s' "${alt}" "${url}"
}

# Compare two versions, ignoring a single leading 'v' on either side.
function versions_match {
  [ "${1#v}" = "${2#v}" ]
}

require_command yq 'yq is required to run this script'

problems=0

for chart_yaml in "${REPO_ROOT}"/charts/*/Chart.yaml; do
  [ -f "${chart_yaml}" ] || continue

  chart_dir="$(dirname "${chart_yaml}")"
  readme="${chart_dir}/README.md"
  label="charts/$(basename "${chart_dir}")/README.md"

  [ -f "${readme}" ] || continue

  version_badge="$(badge_values "${readme}" Version)"
  if [ -z "${version_badge}" ]; then
    # No version badges in this README, nothing to keep in sync.
    continue
  fi

  chart_version="$(yq e '.version // ""' "${chart_yaml}")"
  chart_app_version="$(yq e '.appVersion // ""' "${chart_yaml}")"

  version_alt="${version_badge%% *}"
  version_url="${version_badge##* }"

  if ! versions_match "${version_alt}" "${chart_version}"; then
    print_problem "${label}: Version badge ${version_alt} does not match Chart.yaml version ${chart_version}"
    problems=$((problems + 1))
  fi
  if [ "${version_url}" != "${version_alt}" ]; then
    print_problem "${label}: Version badge text (${version_alt}) and image URL (${version_url}) disagree"
    problems=$((problems + 1))
  fi

  app_badge="$(badge_values "${readme}" AppVersion)"
  if [ -z "${app_badge}" ]; then
    if [ -n "${chart_app_version}" ]; then
      print_problem "${label}: has a Version badge but no AppVersion badge, while Chart.yaml declares appVersion ${chart_app_version}"
      problems=$((problems + 1))
    fi
    continue
  fi

  app_alt="${app_badge%% *}"
  app_url="${app_badge##* }"

  if [ -z "${chart_app_version}" ]; then
    print_problem "${label}: AppVersion badge is ${app_alt} but Chart.yaml declares no appVersion"
    problems=$((problems + 1))
  elif ! versions_match "${app_alt}" "${chart_app_version}"; then
    print_problem "${label}: AppVersion badge ${app_alt} does not match Chart.yaml appVersion ${chart_app_version}"
    problems=$((problems + 1))
  fi
  if [ "${app_url}" != "${app_alt}" ]; then
    print_problem "${label}: AppVersion badge text (${app_alt}) and image URL (${app_url}) disagree"
    problems=$((problems + 1))
  fi
done

if [ "${problems}" -ne 0 ]; then
  print_problem "${problems} README version badge problem(s) found. Update the badges to match Chart.yaml."
  exit 1
fi
