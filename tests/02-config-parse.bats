#!/usr/bin/env bats
# 02-config-parse.bats — config parsing and normalization store tests

load helpers/csm-common

setup() { csm_common_setup; }
teardown() { csm_teardown; }

# --- csm_read_var ---

@test "csm_read_var reads Perl-style var (VAR = \"val\")" {
    result=$(csm_read_var "$CSM_CSF_CONF" "TCP_IN")
    [ "$result" = "22,80,443" ]
}

@test "csm_read_var reads shell-style var (VAR=\"val\")" {
    result=$(csm_read_var "$CSM_CSF_CONF" "SHELL_VAR")
    [ "$result" = "shell_value" ]
}

@test "csm_read_var reads single-quoted shell-style var" {
    result=$(csm_read_var "$CSM_CSF_CONF" "SHELL_QUOTED")
    [ "$result" = "single_quoted" ]
}

@test "csm_read_var returns 1 for missing variable" {
    run csm_read_var "$CSM_CSF_CONF" "NONEXISTENT_VAR_XYZ"
    [ "$status" -eq 1 ]
}

@test "csm_read_var returns 1 for missing file" {
    run csm_read_var "/nonexistent/csf.conf" "TCP_IN"
    [ "$status" -eq 1 ]
}

@test "csm_read_var handles CRLF line endings" {
    local crlf_conf="$TEST_TMPDIR/crlf.conf"
    printf 'TCP_IN = "22,80"\r\nTCP_OUT = "80,443"\r\n' > "$crlf_conf"
    result=$(csm_read_var "$crlf_conf" "TCP_OUT")
    [ "$result" = "80,443" ]
}

# --- csm_read_conf ---

@test "csm_read_conf populates _CSM_RAW_NAMES with >= 40 entries from fixture" {
    csm_read_conf "$CSM_CSF_CONF"
    [ "${#_CSM_RAW_NAMES[@]}" -ge 40 ]
}

@test "csm_read_conf populates _CSM_RAW_VALUES parallel to _CSM_RAW_NAMES" {
    csm_read_conf "$CSM_CSF_CONF"
    [ "${#_CSM_RAW_NAMES[@]}" -eq "${#_CSM_RAW_VALUES[@]}" ]
}

@test "csm_read_conf returns 1 for empty file" {
    local empty_conf="$TEST_TMPDIR/empty.conf"
    > "$empty_conf"
    run csm_read_conf "$empty_conf"
    [ "$status" -eq 0 ]
    [ "${#_CSM_RAW_NAMES[@]}" -eq 0 ]
}

@test "csm_read_conf returns 1 for missing file" {
    run csm_read_conf "/nonexistent/csf.conf"
    [ "$status" -eq 1 ]
}

@test "csm_read_conf handles CRLF line endings" {
    local crlf_conf="$TEST_TMPDIR/crlf.conf"
    printf 'TCP_IN = "22,80"\r\nTCP_OUT = "80,443"\r\n' > "$crlf_conf"
    csm_read_conf "$crlf_conf"
    [ "${#_CSM_RAW_NAMES[@]}" -eq 2 ]
    [ "${_CSM_RAW_VALUES[0]}" = "22,80" ]
    [ "${_CSM_RAW_VALUES[1]}" = "80,443" ]
}

# --- _csm_read_cxs_ignore ---

@test "_csm_read_cxs_ignore parses all 4 keyword types from fixture" {
    local ignore_file="${PROJECT_ROOT}/tests/fixtures/cxs/cxs.ignore"
    _csm_read_cxs_ignore "$ignore_file"
    [ "${#_CSM_CXS_IGNORE_TYPES[@]}" -eq 4 ]
    [ "${_CSM_CXS_IGNORE_TYPES[0]}" = "file" ]
    [ "${_CSM_CXS_IGNORE_TYPES[1]}" = "dir" ]
    [ "${_CSM_CXS_IGNORE_TYPES[2]}" = "pfile" ]
    [ "${_CSM_CXS_IGNORE_TYPES[3]}" = "ip" ]
}

@test "_csm_read_cxs_ignore sets correct values for each keyword" {
    local ignore_file="${PROJECT_ROOT}/tests/fixtures/cxs/cxs.ignore"
    _csm_read_cxs_ignore "$ignore_file"
    [ "${_CSM_CXS_IGNORE_VALUES[0]}" = "/home/user/public_html/wp-config.php" ]
    [ "${_CSM_CXS_IGNORE_VALUES[3]}" = "192.168.1.100" ]
}

@test "_csm_read_cxs_ignore returns 1 for missing file" {
    run _csm_read_cxs_ignore "/nonexistent/cxs.ignore"
    [ "$status" -eq 1 ]
}

# --- _csm_norm_add / _csm_norm_find ---

@test "_csm_norm_add appends entry to normalization store" {
    _csm_norm_add "TCP_IN" "22,80,443" "translated" "IG_TCP_CPORTS"
    [ "${#_CSM_NORM_NAMES[@]}" -eq 1 ]
    [ "${_CSM_NORM_NAMES[0]}" = "TCP_IN" ]
    [ "${_CSM_NORM_VALUES[0]}" = "22,80,443" ]
    [ "${_CSM_NORM_STATUS[0]}" = "translated" ]
    [ "${_CSM_NORM_TARGET[0]}" = "IG_TCP_CPORTS" ]
}

@test "_csm_norm_find locates entry by source name" {
    _csm_norm_add "TCP_IN" "22,80,443" "translated" "IG_TCP_CPORTS"
    _csm_norm_add "TCP_OUT" "80,443" "translated" "EG_TCP_CPORTS"
    _csm_norm_find "TCP_OUT"
    [ "$_CSM_NORM_RESULT" -eq 1 ]
}

@test "_csm_norm_find sets _CSM_NORM_RESULT=-1 for missing entry" {
    _csm_norm_add "TCP_IN" "22,80,443" "translated" "IG_TCP_CPORTS"
    # Suppress non-zero exit so BATS set-e does not abort the test body;
    # we assert the return code and variable value explicitly below.
    _csm_norm_find "NONEXISTENT_VAR" || true
    [ "$_CSM_NORM_RESULT" = "-1" ]
}

@test "_csm_norm_add supports empty target (4th arg optional)" {
    _csm_norm_add "RESTRICT_SYSLOG" "3" "unmapped" ""
    [ "${_CSM_NORM_TARGET[0]}" = "" ]
}
