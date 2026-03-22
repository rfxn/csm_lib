#!/usr/bin/env bats
# 06-trust-migrate.bats — trust list and file migration tests

load helpers/csm-common

setup() { csm_common_setup; }
teardown() { csm_teardown; }

# ---------------------------------------------------------------------------
# csm_migrate_trust_allow
# ---------------------------------------------------------------------------

@test "allow: advanced filter pipe→colon transform" {
    local dst="$TEST_TMPDIR/allow_hosts.rules"
    touch "$dst"
    csm_migrate_trust_allow "${PROJECT_ROOT}/tests/fixtures/csf/csf.allow" "$dst"
    grep -q "tcp:in:d=22:s=10.0.0.0/8" "$dst"
}

@test "allow: simple IP entries copied directly" {
    local dst="$TEST_TMPDIR/allow_hosts.rules"
    touch "$dst"
    csm_migrate_trust_allow "${PROJECT_ROOT}/tests/fixtures/csf/csf.allow" "$dst"
    grep -q "^10.0.0.1$" "$dst"
}

@test "allow: CIDR block copied directly" {
    local dst="$TEST_TMPDIR/allow_hosts.rules"
    touch "$dst"
    csm_migrate_trust_allow "${PROJECT_ROOT}/tests/fixtures/csf/csf.allow" "$dst"
    grep -q "^192.168.1.0/24$" "$dst"
}

@test "allow: idempotent — double-migrate produces no duplicates" {
    local dst="$TEST_TMPDIR/allow_hosts.rules"
    touch "$dst"
    csm_migrate_trust_allow "${PROJECT_ROOT}/tests/fixtures/csf/csf.allow" "$dst"
    csm_migrate_trust_allow "${PROJECT_ROOT}/tests/fixtures/csf/csf.allow" "$dst"
    local count
    count=$(grep -c "tcp:in:d=22:s=10.0.0.0/8" "$dst")
    [ "$count" -eq 1 ]
}

@test "allow: CRLF lines handled (no embedded carriage return in output)" {
    local src="$TEST_TMPDIR/csf.allow.crlf"
    local dst="$TEST_TMPDIR/allow_hosts.rules"
    printf '10.1.1.1\r\ntcp|in|d=22|s=10.0.0.0/8\r\n' > "$src"
    touch "$dst"
    csm_migrate_trust_allow "$src" "$dst"
    # No line in dst should end with \r
    run grep -cP '\r' "$dst"
    [ "$output" = "0" ] || [ "$status" -eq 1 ]
}

@test "allow: report line added with entry count" {
    local dst="$TEST_TMPDIR/allow_hosts.rules"
    touch "$dst"
    csm_migrate_trust_allow "${PROJECT_ROOT}/tests/fixtures/csf/csf.allow" "$dst"
    local found=0
    local line
    for line in "${_CSM_REPORT_LINES[@]}"; do
        if [[ "$line" == *"csf.allow → allow_hosts.rules"* ]]; then
            found=1
            break
        fi
    done
    [ "$found" -eq 1 ]
}

# ---------------------------------------------------------------------------
# csm_migrate_trust_deny
# ---------------------------------------------------------------------------

@test "deny: plain IP entry copied" {
    local dst="$TEST_TMPDIR/deny_hosts.rules"
    touch "$dst"
    csm_migrate_trust_deny "${PROJECT_ROOT}/tests/fixtures/csf/csf.deny" "$dst"
    grep -q "^1.2.3.4" "$dst"
}

@test "deny: temp entry converted to TTL annotation or permanent fallback" {
    local dst="$TEST_TMPDIR/deny_hosts.rules"
    touch "$dst"
    csm_migrate_trust_deny "${PROJECT_ROOT}/tests/fixtures/csf/csf.deny" "$dst"
    # The temp entry "9.10.11.12 # lfd - (sshd) Fri Mar 15 10:30:00 2026 #do not delete"
    # should produce either a ttl= annotation or a permanent fallback annotation
    run grep "9.10.11.12" "$dst"
    [ "$status" -eq 0 ]
    [[ "$output" == *"ttl="* ]] || [[ "$output" == *"permanent"* ]]
}

@test "deny: idempotent — double-migrate no duplicate for plain IP" {
    local dst="$TEST_TMPDIR/deny_hosts.rules"
    touch "$dst"
    csm_migrate_trust_deny "${PROJECT_ROOT}/tests/fixtures/csf/csf.deny" "$dst"
    csm_migrate_trust_deny "${PROJECT_ROOT}/tests/fixtures/csf/csf.deny" "$dst"
    local count
    count=$(grep -c "^1.2.3.4" "$dst")
    [ "$count" -eq 1 ]
}

@test "deny: report line added with temp count" {
    local dst="$TEST_TMPDIR/deny_hosts.rules"
    touch "$dst"
    csm_migrate_trust_deny "${PROJECT_ROOT}/tests/fixtures/csf/csf.deny" "$dst"
    local found=0
    local line
    for line in "${_CSM_REPORT_LINES[@]}"; do
        if [[ "$line" == *"csf.deny → deny_hosts.rules"* ]]; then
            found=1
            break
        fi
    done
    [ "$found" -eq 1 ]
}

# ---------------------------------------------------------------------------
# csm_migrate_trust_sips
# ---------------------------------------------------------------------------

@test "sips: entries copied directly" {
    local dst="$TEST_TMPDIR/silent_ips.rules"
    touch "$dst"
    csm_migrate_trust_sips "${PROJECT_ROOT}/tests/fixtures/csf/csf.sips" "$dst"
    grep -q "^10.0.0.100$" "$dst"
    grep -q "^10.0.0.200$" "$dst"
}

@test "sips: idempotent — double-migrate no duplicates" {
    local dst="$TEST_TMPDIR/silent_ips.rules"
    touch "$dst"
    csm_migrate_trust_sips "${PROJECT_ROOT}/tests/fixtures/csf/csf.sips" "$dst"
    csm_migrate_trust_sips "${PROJECT_ROOT}/tests/fixtures/csf/csf.sips" "$dst"
    local count
    count=$(grep -c "^10.0.0.100$" "$dst")
    [ "$count" -eq 1 ]
}

# ---------------------------------------------------------------------------
# csm_migrate_blocklists
# ---------------------------------------------------------------------------

@test "blocklists: 4-field CSF entry expanded to 7-field rfxn format" {
    local dst="$TEST_TMPDIR/ipset.rules"
    touch "$dst"
    csm_migrate_blocklists "${PROJECT_ROOT}/tests/fixtures/csf/csf.blocklists" "$dst"
    # SPAMDROP|86400|0|https://... → SPAMDROP|hash:ip|URL|86400|0|DROP|Migrated from CSF
    grep -q "^SPAMDROP|hash:ip|https://www.spamhaus.org/drop/drop.txt|86400|0|DROP|Migrated from CSF$" "$dst"
}

@test "blocklists: all fixture entries migrated" {
    local dst="$TEST_TMPDIR/ipset.rules"
    touch "$dst"
    csm_migrate_blocklists "${PROJECT_ROOT}/tests/fixtures/csf/csf.blocklists" "$dst"
    grep -q "^DSHIELD|" "$dst"
}

@test "blocklists: idempotent — double-migrate no duplicates" {
    local dst="$TEST_TMPDIR/ipset.rules"
    touch "$dst"
    csm_migrate_blocklists "${PROJECT_ROOT}/tests/fixtures/csf/csf.blocklists" "$dst"
    csm_migrate_blocklists "${PROJECT_ROOT}/tests/fixtures/csf/csf.blocklists" "$dst"
    local count
    count=$(grep -c "^SPAMDROP|" "$dst")
    [ "$count" -eq 1 ]
}

# ---------------------------------------------------------------------------
# csm_migrate_cxs_ignore
# ---------------------------------------------------------------------------

@test "cxs_ignore: file: keyword written to hex.dat" {
    mkdir -p "$TEST_TMPDIR/ignore"
    touch "$TEST_TMPDIR/ignore/hex.dat"
    csm_migrate_cxs_ignore "${PROJECT_ROOT}/tests/fixtures/cxs" "$TEST_TMPDIR"
    grep -q "/home/user/public_html/wp-config.php" "$TEST_TMPDIR/ignore/hex.dat"
}

@test "cxs_ignore: dir: keyword written to path.dat" {
    mkdir -p "$TEST_TMPDIR/ignore"
    touch "$TEST_TMPDIR/ignore/path.dat"
    csm_migrate_cxs_ignore "${PROJECT_ROOT}/tests/fixtures/cxs" "$TEST_TMPDIR"
    grep -q "/home/user/public_html/cache" "$TEST_TMPDIR/ignore/path.dat"
}

@test "cxs_ignore: pfile: keyword (regex) written to regex.dat" {
    mkdir -p "$TEST_TMPDIR/ignore"
    touch "$TEST_TMPDIR/ignore/regex.dat"
    csm_migrate_cxs_ignore "${PROJECT_ROOT}/tests/fixtures/cxs" "$TEST_TMPDIR"
    grep -q '\\/home\\/.*\\/error_log\$' "$TEST_TMPDIR/ignore/regex.dat"
}

@test "cxs_ignore: ip: keyword skipped and reported" {
    mkdir -p "$TEST_TMPDIR/ignore"
    touch "$TEST_TMPDIR/ignore/hex.dat" "$TEST_TMPDIR/ignore/path.dat" "$TEST_TMPDIR/ignore/regex.dat"
    csm_migrate_cxs_ignore "${PROJECT_ROOT}/tests/fixtures/cxs" "$TEST_TMPDIR"
    # ip: entry should NOT appear in any ignore dat file
    run grep -r "192.168.1.100" "$TEST_TMPDIR/ignore/"
    [ "$status" -ne 0 ]
}

@test "cxs_ignore: ip: keyword generates skip report line" {
    mkdir -p "$TEST_TMPDIR/ignore"
    touch "$TEST_TMPDIR/ignore/hex.dat" "$TEST_TMPDIR/ignore/path.dat" "$TEST_TMPDIR/ignore/regex.dat"
    csm_migrate_cxs_ignore "${PROJECT_ROOT}/tests/fixtures/cxs" "$TEST_TMPDIR"
    local found=0
    local line
    for line in "${_CSM_REPORT_LINES[@]}"; do
        if [[ "$line" == *"ip:"*"skipped"* ]]; then
            found=1
            break
        fi
    done
    [ "$found" -eq 1 ]
}

# ---------------------------------------------------------------------------
# csm_migrate_lfd_ignore
# ---------------------------------------------------------------------------

@test "lfd_ignore: entries copied directly" {
    local dst="$TEST_TMPDIR/allow.hosts"
    touch "$dst"
    csm_migrate_lfd_ignore "${PROJECT_ROOT}/tests/fixtures/csf/csf.ignore" "$dst"
    grep -q "^10.0.0.0/8$" "$dst"
    grep -q "^192.168.1.1$" "$dst"
}

@test "lfd_ignore: idempotent — double-migrate no duplicates" {
    local dst="$TEST_TMPDIR/allow.hosts"
    touch "$dst"
    csm_migrate_lfd_ignore "${PROJECT_ROOT}/tests/fixtures/csf/csf.ignore" "$dst"
    csm_migrate_lfd_ignore "${PROJECT_ROOT}/tests/fixtures/csf/csf.ignore" "$dst"
    local count
    count=$(grep -c "^10.0.0.0/8$" "$dst")
    [ "$count" -eq 1 ]
}
