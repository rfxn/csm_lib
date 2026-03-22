#!/bin/bash
#
# csm_lib Test Runner — batsman integration wrapper
# Usage: ./tests/run-tests.sh [--os OS] [--parallel [N]] [bats args...]
#
set -e

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

# Variables consumed by sourced run-tests-core.sh
# shellcheck disable=SC2034
BATSMAN_PROJECT="csm"
# shellcheck disable=SC2034
BATSMAN_PROJECT_DIR="$(cd "$SCRIPT_DIR/.." && pwd)"
# shellcheck disable=SC2034
BATSMAN_TESTS_DIR="$SCRIPT_DIR"
BATSMAN_INFRA_DIR="$SCRIPT_DIR/infra"
# shellcheck disable=SC2034
BATSMAN_DOCKER_FLAGS=""
# shellcheck disable=SC2034
BATSMAN_DEFAULT_OS="debian12"
# shellcheck disable=SC2034
BATSMAN_CONTAINER_TEST_PATH="/opt/tests"
# shellcheck disable=SC2034
BATSMAN_SUPPORTED_OS="debian12 centos6 centos7 rocky8 rocky9 rocky10 ubuntu2004 ubuntu2404"

# Copy pkg_lib into tests/deps/ for container inclusion
PKG_LIB_SRC="$(cd "$SCRIPT_DIR/.." && pwd)/../pkg_lib/files/pkg_lib.sh"
PKG_LIB_DEST="$SCRIPT_DIR/deps/pkg_lib.sh"
if [[ -f "$PKG_LIB_SRC" ]]; then
    mkdir -p "$SCRIPT_DIR/deps"
    /usr/bin/cp -f "$PKG_LIB_SRC" "$PKG_LIB_DEST"
fi

# shellcheck source=/dev/null
source "$BATSMAN_INFRA_DIR/lib/run-tests-core.sh"
batsman_run "$@"
