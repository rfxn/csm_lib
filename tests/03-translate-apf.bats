#!/usr/bin/env bats
# 03-translate-apf.bats — CSF→APF translation tests

load helpers/csm-common

setup() { csm_common_setup; }
teardown() { csm_teardown; }

# Helper: run csm_translate_apf once for all tests that need it.
# Stores state in module-level arrays (already global from library).
_run_translate() {
    csm_translate_apf
}

# --- Transform: direct ---

@test "TCP_IN maps to IG_TCP_CPORTS with value preserved (direct)" {
    _run_translate
    _csm_norm_find "TCP_IN"
    local idx="$_CSM_NORM_RESULT"
    [ "$idx" -ge 0 ]
    [ "${_CSM_NORM_STATUS[$idx]}" = "translated" ]
    [ "${_CSM_NORM_TARGET[$idx]}" = "IG_TCP_CPORTS" ]
    [ "${_CSM_NORM_VALUES[$idx]}" = "22,80,443" ]
}

# --- Transform: direct+egf ---

@test "TCP_OUT maps to EG_TCP_CPORTS and sets EGF side effect (direct+egf)" {
    _run_translate
    # Check TCP_OUT translated entry
    _csm_norm_find "TCP_OUT"
    local idx="$_CSM_NORM_RESULT"
    [ "$idx" -ge 0 ]
    [ "${_CSM_NORM_STATUS[$idx]}" = "translated" ]
    [ "${_CSM_NORM_TARGET[$idx]}" = "EG_TCP_CPORTS" ]
    # Check EGF side-effect entry
    _csm_norm_find "EGF"
    local egf_idx="$_CSM_NORM_RESULT"
    [ "$egf_idx" -ge 0 ]
    [ "${_CSM_NORM_VALUES[$egf_idx]}" = "1" ]
    [ "${_CSM_NORM_STATUS[$egf_idx]}" = "translated" ]
}

# --- Transform: append_s ---

@test "SYNFLOOD_RATE already has /s — not double-appended" {
    _run_translate
    _csm_norm_find "SYNFLOOD_RATE"
    local idx="$_CSM_NORM_RESULT"
    [ "$idx" -ge 0 ]
    [ "${_CSM_NORM_VALUES[$idx]}" = "100/s" ]
}

@test "append_s adds /s when value lacks it" {
    # Create a temp conf with SYNFLOOD_RATE without /s
    local tmp_conf="$TEST_TMPDIR/csf_nosuffix.conf"
    printf 'SYNFLOOD_RATE = "100"\n' > "$tmp_conf"
    CSM_CSF_CONF="$tmp_conf"
    csm_translate_apf
    _csm_norm_find "SYNFLOOD_RATE"
    local idx="$_CSM_NORM_RESULT"
    [ "$idx" -ge 0 ]
    [ "${_CSM_NORM_VALUES[$idx]}" = "100/s" ]
}

# --- Transform: sep_semi_colon ---

@test "CONNLIMIT semicolons replaced with colons (sep_semi_colon)" {
    _run_translate
    _csm_norm_find "CONNLIMIT"
    local idx="$_CSM_NORM_RESULT"
    [ "$idx" -ge 0 ]
    [ "${_CSM_NORM_TARGET[$idx]}" = "IG_TCP_CLIMIT" ]
    [ "${_CSM_NORM_VALUES[$idx]}" = "22:5,80:20" ]
}

# --- Transform: expand_drop ---

@test "DROP expands to TCP_STOP UDP_STOP ALL_STOP (expand_drop)" {
    _run_translate
    _csm_norm_find "TCP_STOP"
    local tcp_idx="$_CSM_NORM_RESULT"
    [ "$tcp_idx" -ge 0 ]
    [ "${_CSM_NORM_VALUES[$tcp_idx]}" = "DROP" ]
    [ "${_CSM_NORM_STATUS[$tcp_idx]}" = "translated" ]

    _csm_norm_find "UDP_STOP"
    local udp_idx="$_CSM_NORM_RESULT"
    [ "$udp_idx" -ge 0 ]
    [ "${_CSM_NORM_VALUES[$udp_idx]}" = "DROP" ]

    _csm_norm_find "ALL_STOP"
    local all_idx="$_CSM_NORM_RESULT"
    [ "$all_idx" -ge 0 ]
    [ "${_CSM_NORM_VALUES[$all_idx]}" = "DROP" ]
}

# --- Transform: gap ---

@test "gap variables have status=gap with target version string" {
    _run_translate
    _csm_norm_find "PORTFLOOD"
    local idx="$_CSM_NORM_RESULT"
    [ "$idx" -ge 0 ]
    [ "${_CSM_NORM_STATUS[$idx]}" = "gap" ]
    # Target must contain version info
    [[ "${_CSM_NORM_TARGET[$idx]}" == *"APF"* ]]
}

@test "CC_DENY and CC_ALLOW are gap variables with target version" {
    _run_translate
    _csm_norm_find "CC_DENY"
    local idx="$_CSM_NORM_RESULT"
    [ "$idx" -ge 0 ]
    [ "${_CSM_NORM_STATUS[$idx]}" = "gap" ]
    [[ "${_CSM_NORM_TARGET[$idx]}" == *"APF"* ]]
}

# --- Transform: log_bfd ---

@test "LFD variables are marked log_bfd status" {
    _run_translate
    _csm_norm_find "LF_SSHD"
    local idx="$_CSM_NORM_RESULT"
    [ "$idx" -ge 0 ]
    [ "${_CSM_NORM_STATUS[$idx]}" = "log_bfd" ]
    [[ "${_CSM_NORM_TARGET[$idx]}" == *"BFD"* ]]
}

# --- Unmapped variables ---

@test "unmapped vars have status=unmapped" {
    _run_translate
    _csm_norm_find "RESTRICT_SYSLOG"
    local idx="$_CSM_NORM_RESULT"
    [ "$idx" -ge 0 ]
    [ "${_CSM_NORM_STATUS[$idx]}" = "unmapped" ]
    # Target is empty for unmapped
    [ "${_CSM_NORM_TARGET[$idx]}" = "" ]
}

@test "MESSENGER and CLUSTER_SENDTO are also unmapped" {
    _run_translate
    _csm_norm_find "MESSENGER"
    local m_idx="$_CSM_NORM_RESULT"
    [ "$m_idx" -ge 0 ]
    [ "${_CSM_NORM_STATUS[$m_idx]}" = "unmapped" ]

    _csm_norm_find "CLUSTER_SENDTO"
    local c_idx="$_CSM_NORM_RESULT"
    [ "$c_idx" -ge 0 ]
    [ "${_CSM_NORM_STATUS[$c_idx]}" = "unmapped" ]
}

# --- Totals ---

@test "csm_translate_apf produces >=34 mapped entries (translated+log_bfd) from fixture" {
    # log_bfd entries are mapped vars redirected to BFD; both count toward total
    # mapped coverage. The fixture yields ~31 translated + 7 log_bfd = 38 total.
    _run_translate
    local count=0
    local i
    for i in "${!_CSM_NORM_STATUS[@]}"; do
        if [[ "${_CSM_NORM_STATUS[$i]}" == "translated" || "${_CSM_NORM_STATUS[$i]}" == "log_bfd" ]]; then
            (( count++ )) || true
        fi
    done
    [ "$count" -ge 34 ]
}

@test "csm_translate_apf produces >=5 gap entries from fixture" {
    _run_translate
    local count=0
    local i
    for i in "${!_CSM_NORM_STATUS[@]}"; do
        if [[ "${_CSM_NORM_STATUS[$i]}" == "gap" ]]; then
            (( count++ )) || true
        fi
    done
    [ "$count" -ge 5 ]
}

@test "csm_translate_apf produces >=5 unmapped entries from fixture" {
    _run_translate
    local count=0
    local i
    for i in "${!_CSM_NORM_STATUS[@]}"; do
        if [[ "${_CSM_NORM_STATUS[$i]}" == "unmapped" ]]; then
            (( count++ )) || true
        fi
    done
    [ "$count" -ge 5 ]
}

# --- Empty value ---

@test "empty CSF value (CC_ALLOW=\"\") is translated with empty string preserved" {
    _run_translate
    _csm_norm_find "CC_ALLOW"
    local idx="$_CSM_NORM_RESULT"
    [ "$idx" -ge 0 ]
    # CC_ALLOW is a gap var — value still stored
    [ "${_CSM_NORM_VALUES[$idx]}" = "" ]
}

# --- Re-entry safety ---

@test "csm_translate_apf is re-entry safe — calling twice gives same TCP_IN result" {
    csm_translate_apf
    csm_translate_apf
    # After second call arrays are rebuilt cleanly — _csm_norm_find returns one hit
    local count=0
    local i
    for i in "${!_CSM_NORM_NAMES[@]}"; do
        if [[ "${_CSM_NORM_NAMES[$i]}" == "TCP_IN" ]]; then
            (( count++ )) || true
        fi
    done
    # Exactly one entry for TCP_IN
    [ "$count" -eq 1 ]
}
