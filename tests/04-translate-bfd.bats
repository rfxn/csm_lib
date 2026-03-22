#!/usr/bin/env bats
# 04-translate-bfd.bats — LFD→BFD pressure model translation tests

load helpers/csm-common

setup() { csm_common_setup; }
teardown() { csm_teardown; }

# Helper: run csm_translate_bfd once for all tests that need it.
_run_translate_bfd() {
    csm_translate_bfd
}

# Helper: find rule index by name in BFD arrays
_bfd_find() {
    local rule_name="$1" i
    _CSM_BFD_FIND_IDX=-1
    for i in "${!_CSM_BFD_RULES[@]}"; do
        if [[ "${_CSM_BFD_RULES[$i]}" == "$rule_name" ]]; then
            _CSM_BFD_FIND_IDX="$i"
            return 0
        fi
    done
    return 1
}

# --- Pressure formula: basic calibration ---

@test "LF_SSHD=5 produces SSHD rule with trip=15 (5*3)" {
    _run_translate_bfd
    _bfd_find "SSHD"
    [ "$_CSM_BFD_FIND_IDX" -ge 0 ]
    [ "${_CSM_BFD_TRIPS[$_CSM_BFD_FIND_IDX]}" -eq 15 ]
}

@test "LF_FTPD=10 produces FTPD rule with trip=30 (10*3)" {
    _run_translate_bfd
    _bfd_find "FTPD"
    [ "$_CSM_BFD_FIND_IDX" -ge 0 ]
    [ "${_CSM_BFD_TRIPS[$_CSM_BFD_FIND_IDX]}" -eq 30 ]
}

# --- Pressure formula: clamp ---

@test "high trigger value (100) produces trip clamped to 200" {
    local tmp_conf="$TEST_TMPDIR/csf_highval.conf"
    printf 'LF_SSHD = "100"\n' > "$tmp_conf"
    CSM_CSF_CONF="$tmp_conf"
    csm_translate_bfd
    _bfd_find "SSHD"
    [ "$_CSM_BFD_FIND_IDX" -ge 0 ]
    [ "${_CSM_BFD_TRIPS[$_CSM_BFD_FIND_IDX]}" -eq 200 ]
}

@test "trigger value 67 produces trip clamped to 200 (67*3=201 > 200)" {
    local tmp_conf="$TEST_TMPDIR/csf_borderclamp.conf"
    printf 'LF_SSHD = "67"\n' > "$tmp_conf"
    CSM_CSF_CONF="$tmp_conf"
    csm_translate_bfd
    _bfd_find "SSHD"
    [ "$_CSM_BFD_FIND_IDX" -ge 0 ]
    [ "${_CSM_BFD_TRIPS[$_CSM_BFD_FIND_IDX]}" -eq 200 ]
}

# --- Edge case: trigger=0 (disabled) ---

@test "LF trigger value 0 produces trip=0 (disabled, not clamped)" {
    local tmp_conf="$TEST_TMPDIR/csf_zero.conf"
    printf 'LF_SSHD = "0"\n' > "$tmp_conf"
    CSM_CSF_CONF="$tmp_conf"
    csm_translate_bfd
    _bfd_find "SSHD"
    [ "$_CSM_BFD_FIND_IDX" -ge 0 ]
    [ "${_CSM_BFD_TRIPS[$_CSM_BFD_FIND_IDX]}" -eq 0 ]
}

# --- Direct mappings ---

@test "LF_TRIGGER_PERM maps to BAN_TTL with value 3600" {
    _run_translate_bfd
    _bfd_find "BAN_TTL"
    [ "$_CSM_BFD_FIND_IDX" -ge 0 ]
    [ "${_CSM_BFD_TRIPS[$_CSM_BFD_FIND_IDX]}" = "3600" ]
}

@test "LF_ALERT_TO maps to EMAIL_ADDRESS with correct value" {
    _run_translate_bfd
    _bfd_find "EMAIL_ADDRESS"
    [ "$_CSM_BFD_FIND_IDX" -ge 0 ]
    [ "${_CSM_BFD_TRIPS[$_CSM_BFD_FIND_IDX]}" = "admin@example.com" ]
}

# --- LF_SELECT always maps to FIREWALL=apf ---

@test "LF_SELECT maps to FIREWALL with value apf regardless of original" {
    _run_translate_bfd
    _bfd_find "FIREWALL"
    [ "$_CSM_BFD_FIND_IDX" -ge 0 ]
    [ "${_CSM_BFD_TRIPS[$_CSM_BFD_FIND_IDX]}" = "apf" ]
}
