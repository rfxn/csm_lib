#!/usr/bin/env bats
# 05-translate-lmd.bats — CXS→LMD translation tests

load helpers/csm-common

setup() { csm_common_setup; }
teardown() { csm_teardown; }

# Helper: run csm_translate_lmd once for all tests that need it.
_run_translate_lmd() {
    csm_translate_lmd
}

# Helper: find index of norm entry by source name
_lmd_find() {
    local src_name="$1"
    _csm_norm_find "$src_name"
}

# --- Direct mappings ---

@test "CXS_QUARANTINE maps to quarantine_hits with correct value" {
    _run_translate_lmd
    _lmd_find "CXS_QUARANTINE"
    local idx="$_CSM_NORM_RESULT"
    [ "$idx" -ge 0 ]
    [ "${_CSM_NORM_STATUS[$idx]}" = "translated" ]
    [ "${_CSM_NORM_TARGET[$idx]}" = "quarantine_hits" ]
    [ "${_CSM_NORM_VALUES[$idx]}" = "1" ]
}

@test "CXS_ALERT_TO maps to email_addr with correct value" {
    _run_translate_lmd
    _lmd_find "CXS_ALERT_TO"
    local idx="$_CSM_NORM_RESULT"
    [ "$idx" -ge 0 ]
    [ "${_CSM_NORM_STATUS[$idx]}" = "translated" ]
    [ "${_CSM_NORM_TARGET[$idx]}" = "email_addr" ]
    [ "${_CSM_NORM_VALUES[$idx]}" = "admin@example.com" ]
}

@test "CXS_CLAMAV maps to scan_clamscan with correct value" {
    _run_translate_lmd
    _lmd_find "CXS_CLAMAV"
    local idx="$_CSM_NORM_RESULT"
    [ "$idx" -ge 0 ]
    [ "${_CSM_NORM_STATUS[$idx]}" = "translated" ]
    [ "${_CSM_NORM_TARGET[$idx]}" = "scan_clamscan" ]
    [ "${_CSM_NORM_VALUES[$idx]}" = "1" ]
}

# --- Special transform: CXS_WATCH=1 → default_monitor_mode=users ---

@test "CXS_WATCH=1 maps to default_monitor_mode=users (not direct copy)" {
    _run_translate_lmd
    _lmd_find "CXS_WATCH"
    local idx="$_CSM_NORM_RESULT"
    [ "$idx" -ge 0 ]
    [ "${_CSM_NORM_STATUS[$idx]}" = "translated" ]
    [ "${_CSM_NORM_TARGET[$idx]}" = "default_monitor_mode" ]
    [ "${_CSM_NORM_VALUES[$idx]}" = "users" ]
}

@test "CXS_WATCH=0 maps to default_monitor_mode=disabled" {
    local tmp_conf="$TEST_TMPDIR/cxswatch_zero.conf"
    printf 'CXS_WATCH="0"\n' > "$tmp_conf"
    CSM_CXS_WATCHCONF="$tmp_conf"
    csm_translate_lmd
    _lmd_find "CXS_WATCH"
    local idx="$_CSM_NORM_RESULT"
    [ "$idx" -ge 0 ]
    [ "${_CSM_NORM_VALUES[$idx]}" = "disabled" ]
}

# --- Special transform: CXS_MAXFILESIZE bytes→k ---

@test "CXS_MAXFILESIZE 1048576 bytes converts to 1024k" {
    _run_translate_lmd
    _lmd_find "CXS_MAXFILESIZE"
    local idx="$_CSM_NORM_RESULT"
    [ "$idx" -ge 0 ]
    [ "${_CSM_NORM_STATUS[$idx]}" = "translated" ]
    [ "${_CSM_NORM_TARGET[$idx]}" = "scan_max_filesize" ]
    [ "${_CSM_NORM_VALUES[$idx]}" = "1024" ]
}

# --- Auto-set: scan_yara=1 ---

@test "scan_yara auto-enabled (LMD always enables YARA when available)" {
    _run_translate_lmd
    _lmd_find "scan_yara"
    local idx="$_CSM_NORM_RESULT"
    [ "$idx" -ge 0 ]
    [ "${_CSM_NORM_STATUS[$idx]}" = "translated" ]
    [ "${_CSM_NORM_VALUES[$idx]}" = "1" ]
}

# --- Gap variables ---

@test "CXS_FTP_UPLOAD is logged as gap (no LMD equivalent)" {
    local tmp_conf="$TEST_TMPDIR/cxs_ftp.defaults"
    printf 'CXS_FTP_UPLOAD="1"\n' > "$tmp_conf"
    CSM_CXS_DEFAULTS="$tmp_conf"
    csm_translate_lmd
    _lmd_find "CXS_FTP_UPLOAD"
    local idx="$_CSM_NORM_RESULT"
    [ "$idx" -ge 0 ]
    [ "${_CSM_NORM_STATUS[$idx]}" = "gap" ]
}

@test "CXS_UI_APP is logged as gap (no LMD equivalent)" {
    local tmp_conf="$TEST_TMPDIR/cxs_ui.defaults"
    printf 'CXS_UI_APP="cPanel"\n' > "$tmp_conf"
    CSM_CXS_DEFAULTS="$tmp_conf"
    csm_translate_lmd
    _lmd_find "CXS_UI_APP"
    local idx="$_CSM_NORM_RESULT"
    [ "$idx" -ge 0 ]
    [ "${_CSM_NORM_STATUS[$idx]}" = "gap" ]
}

# --- CXS script CLI captured ---

@test "CXS cxswatch.sh CLI invocation line captured in report lines" {
    _run_translate_lmd
    local found=0
    local line
    for line in "${_CSM_REPORT_LINES[@]}"; do
        if [[ "$line" == *"cxs"* && "$line" == *"--cwatch"* ]]; then
            found=1
            break
        fi
    done
    [ "$found" -eq 1 ]
}

# --- Total translated count ---

@test "csm_translate_lmd produces >=20 translated entries from fixtures" {
    _run_translate_lmd
    local count=0
    local i
    for i in "${!_CSM_NORM_STATUS[@]}"; do
        if [[ "${_CSM_NORM_STATUS[$i]}" == "translated" ]]; then
            (( count++ )) || true
        fi
    done
    [ "$count" -ge 20 ]
}

# --- Edge case: no cxs.defaults (detect returns 1) ---

@test "csm_translate_lmd returns 1 when cxs.defaults is missing" {
    CSM_CXS_DEFAULTS="$TEST_TMPDIR/nonexistent.defaults"
    run csm_translate_lmd
    [ "$status" -eq 1 ]
}

# --- Re-entry safety ---

@test "csm_translate_lmd is re-entry safe — calling twice gives same CXS_QUARANTINE result" {
    csm_translate_lmd
    csm_translate_lmd
    local count=0
    local i
    for i in "${!_CSM_NORM_NAMES[@]}"; do
        if [[ "${_CSM_NORM_NAMES[$i]}" == "CXS_QUARANTINE" ]]; then
            (( count++ )) || true
        fi
    done
    [ "$count" -eq 1 ]
}
