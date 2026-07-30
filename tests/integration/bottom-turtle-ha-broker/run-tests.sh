#!/usr/bin/env bash

set -xe

SCRIPT="$(readlink -f "$0")"
SCRIPTPATH="$(dirname "${SCRIPT}")"

# Run the bottom-turtle-ha example test with the spire-ha-agent broker api enabled.
exec "${SCRIPTPATH}/../../../examples/bottom-turtle-ha/run-tests.sh" -b "$@"
