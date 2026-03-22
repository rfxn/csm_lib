#!/usr/bin/env bats
# 01-detection.bats — CSF/LFD/CXS detection tests

load helpers/csm-common

setup() { csm_common_setup; }
teardown() { csm_teardown; }

# --- csm_detect_csf ---

@test "csm_detect_csf returns 0 with fixture csf.conf" {
    run csm_detect_csf
    [ "$status" -eq 0 ]
}

@test "csm_detect_csf sets _CSM_CSF_VERSION from fixture" {
    csm_detect_csf
    [ "$_CSM_CSF_VERSION" = "14.20" ]
}

@test "csm_detect_csf returns 1 when CSM_CSF_CONF does not exist" {
    CSM_CSF_CONF="/nonexistent/path/csf.conf"
    run csm_detect_csf
    [ "$status" -eq 1 ]
}

@test "csm_detect_csf honors CSM_CSF_CONF env var override" {
    local alt_conf="$TEST_TMPDIR/alt-csf.conf"
    printf 'VERSION = "99.99"\n' > "$alt_conf"
    CSM_CSF_CONF="$alt_conf"
    csm_detect_csf
    [ "$_CSM_CSF_VERSION" = "99.99" ]
}

# --- csm_detect_lfd ---

@test "csm_detect_lfd returns 0 when LF_ vars present in csf.conf" {
    run csm_detect_lfd
    [ "$status" -eq 0 ]
}

@test "csm_detect_lfd sets _CSM_LFD_FOUND=1 when LF_ vars present" {
    csm_detect_lfd
    [ "$_CSM_LFD_FOUND" -eq 1 ]
}

@test "csm_detect_lfd returns 1 when csf.conf absent and no lfd binary" {
    CSM_CSF_CONF="/nonexistent/path/csf.conf"
    # Ensure lfd binary is not in PATH for this test
    if command -v lfd >/dev/null 2>&1; then
        skip "lfd binary present on host — cannot test absence"
    fi
    run csm_detect_lfd
    [ "$status" -eq 1 ]
}

# --- csm_detect_cxs ---

@test "csm_detect_cxs returns 0 with fixture cxs.defaults" {
    run csm_detect_cxs
    [ "$status" -eq 0 ]
}

@test "csm_detect_cxs sets _CSM_CXS_FOUND=1 with fixture" {
    csm_detect_cxs
    [ "$_CSM_CXS_FOUND" -eq 1 ]
}

@test "csm_detect_cxs returns 1 when cxs.defaults absent" {
    CSM_CXS_DEFAULTS="/nonexistent/path/cxs.defaults"
    run csm_detect_cxs
    [ "$status" -eq 1 ]
}

@test "csm_detect_cxs checks cxs.defaults, not cxs.conf" {
    # cxs.conf does not exist in fixture dir; cxs.defaults does
    local cxs_conf="${PROJECT_ROOT}/tests/fixtures/cxs/cxs.conf"
    [ ! -f "$cxs_conf" ]
    # csm_detect_cxs must still succeed (uses cxs.defaults)
    run csm_detect_cxs
    [ "$status" -eq 0 ]
}
