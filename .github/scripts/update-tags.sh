#!/usr/bin/env bash

SCRIPT="$(readlink -f "$0")"
SCRIPTPATH="$(dirname "${SCRIPT}")"

IMAGEJSON="${SCRIPTPATH}/../tests/images.json"

if ! command -v crane &> /dev/null; then
  echo Please install crane
  exit 1
fi

if ! command -v jq &> /dev/null; then
  echo Please install jq
  exit 1
fi

if ! command -v yq &> /dev/null; then
  echo Please install yq
  exit 1
fi

if ! command -v npm &> /dev/null; then
  echo Please install npm
  exit 1
fi

if ! command -v python3 -c 'import ruamel.yaml' &> /dev/null; then
  echo Please install python3 with the ruamel.yaml module
  exit 1
fi

if ! command -v python3 -c 'import dict_deep' &> /dev/null; then
  echo Please install python3 with the dict_deep module
  exit 1
fi

jq -r '. | keys[]' "$IMAGEJSON" | while read -r CHART; do
  jq -r ".\"${CHART}\" | keys[]" "$IMAGEJSON" | while read -r IDX; do
    QUERY=$(jq -r ".\"${CHART}\"[${IDX}].query" "$IMAGEJSON")
    FILTER=$(jq -r ".\"${CHART}\"[${IDX}].filter" "$IMAGEJSON")

    OLD_IFS=${IFS}
    SORTFLAGS=()
    while IFS='' read -r value; do
      SORTFLAGS+=("$value")
    done < <(jq -r ".\"${CHART}\"[${IDX}].\"sort-flags\" | .[]" "$IMAGEJSON")
    IFS=${OLD_IFS}

    VALUES="${SCRIPTPATH}/../../charts/spire/charts/${CHART}"
    REGISTRY=$(yq e ".${QUERY}.registry" "$VALUES")
    REPOSITORY=$(yq e ".${QUERY}.repository" "$VALUES")
    VERSION=$(yq e ".${QUERY}.tag" "$VALUES")
    if [[ "$REGISTRY" != "" ]]; then
      REGISTRY="$REGISTRY/"
    fi
    if [[ "$FILTER" == "LATESTSHA" ]]; then
      LATEST_VERSION="latest@"$(crane digest "${REGISTRY}${REPOSITORY}:latest")
    else
      LATEST_VERSION=$(crane ls "${REGISTRY}${REPOSITORY}" | grep "${FILTER}" | sort "${SORTFLAGS[@]}" | tail -n 1)
    fi

    export QUERY
    export VALUES
    export LATEST_VERSION

    if [ "${VERSION}" != "${LATEST_VERSION}" ]; then
      echo "New image version found: ${REGISTRY}${REPOSITORY}:${LATEST_VERSION}"
      "${SCRIPTPATH}/edit-yaml.py" > /tmp/$$
      mv /tmp/$$ "${VALUES}"
    fi
  done
done
"${SCRIPTPATH}/../../helm-docs.sh"
