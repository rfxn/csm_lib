#!/usr/bin/env bats
# 00-scaffold.bats — validate project skeleton

load helpers/csm-common

setup() { csm_common_setup; }
teardown() { csm_teardown; }

@test "CSM_LIB_VERSION is set and follows semver" {
    [[ -n "$EXPECTED_VERSION" ]]
    local semver_pat='^[0-9]+\.[0-9]+\.[0-9]+$'
    [[ "$EXPECTED_VERSION" =~ $semver_pat ]]
}

@test "source guard prevents double-sourcing side effects" {
    local ver_before="$CSM_LIB_VERSION"
    # shellcheck disable=SC1091
    source "${PROJECT_ROOT}/files/csm_lib.sh"
    [[ "$CSM_LIB_VERSION" == "$ver_before" ]]
}

@test "FATAL if pkg_lib not loaded" {
    _PKG_LIB_LOADED=""
    _CSM_LIB_LOADED=""
    run bash -c "source '${PROJECT_ROOT}/files/csm_lib.sh' 2>&1"
    [[ "$output" == *"FATAL"* ]]
    [[ "$status" -ne 0 ]]
}

@test "csm_reset clears all state arrays" {
    _CSM_NORM_NAMES+=("test")
    _CSM_REPORT_LINES+=("test")
    csm_reset
    [[ ${#_CSM_NORM_NAMES[@]} -eq 0 ]]
    [[ ${#_CSM_REPORT_LINES[@]} -eq 0 ]]
}
