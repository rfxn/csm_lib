#!/bin/bash
# csm-common.bash — shared BATS helper for csm_lib tests

PROJECT_ROOT="$(cd "${BATS_TEST_DIRNAME}/.." && pwd)" || return 1
export PROJECT_ROOT

# Source pkg_lib (hard dependency) — look in test deps or sibling project
if [[ -f "${PROJECT_ROOT}/tests/deps/pkg_lib.sh" ]]; then
    # shellcheck disable=SC1091
    source "${PROJECT_ROOT}/tests/deps/pkg_lib.sh"
elif [[ -f "${PROJECT_ROOT}/../pkg_lib/files/pkg_lib.sh" ]]; then
    # shellcheck disable=SC1091
    source "${PROJECT_ROOT}/../pkg_lib/files/pkg_lib.sh"
else
    echo "FATAL: pkg_lib.sh not found" >&2
    exit 1
fi

# Source library under test
# shellcheck disable=SC1091
source "${PROJECT_ROOT}/files/csm_lib.sh"

EXPECTED_VERSION="$CSM_LIB_VERSION"
export EXPECTED_VERSION

# Load bats-support and bats-assert if available
if [[ -d /usr/local/lib/bats/bats-support ]]; then
    # shellcheck disable=SC1091
    source /usr/local/lib/bats/bats-support/load.bash
    # shellcheck disable=SC1091
    source /usr/local/lib/bats/bats-assert/load.bash
fi

csm_common_setup() {
    TEST_TMPDIR=$(mktemp -d)
    export TEST_TMPDIR

    # Reset source guard for clean state
    _CSM_LIB_LOADED=""
    _PKG_LIB_LOADED=""
    # Re-source both
    # shellcheck disable=SC1091
    source "${PROJECT_ROOT}/tests/deps/pkg_lib.sh" 2>/dev/null \
        || source "${PROJECT_ROOT}/../pkg_lib/files/pkg_lib.sh"
    # shellcheck disable=SC1091
    source "${PROJECT_ROOT}/files/csm_lib.sh"

    # Set fixture paths
    CSM_CSF_CONF="${PROJECT_ROOT}/tests/fixtures/csf/csf.conf"
    CSM_CSF_DIR="${PROJECT_ROOT}/tests/fixtures/csf"
    CSM_CXS_DIR="${PROJECT_ROOT}/tests/fixtures/cxs"
    CSM_CXS_DEFAULTS="${PROJECT_ROOT}/tests/fixtures/cxs/cxs.defaults"
    CSM_CXS_WATCHCONF="${PROJECT_ROOT}/tests/fixtures/cxs/cxswatch.conf"
    CSM_DRY_RUN="0"
    CSM_REPORT_FILE="$TEST_TMPDIR/migration-report.log"
    export CSM_CSF_CONF CSM_CSF_DIR CSM_CXS_DIR CSM_CXS_DEFAULTS
    export CSM_CXS_WATCHCONF CSM_DRY_RUN CSM_REPORT_FILE
}

csm_teardown() {
    rm -rf "$TEST_TMPDIR"
}
