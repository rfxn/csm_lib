#!/usr/bin/env bats
# 09-dryrun.bats — CSM_DRY_RUN=1 gate tests across all write paths
# shellcheck disable=SC2030,SC2031  # BATS @test blocks: subshell scoping is expected behavior

load helpers/csm-common

setup() {
    csm_common_setup
    CSM_DRY_RUN="1"
    export CSM_DRY_RUN

    # Prepare a writable APF-style config in TEST_TMPDIR
    MOCK_CONF="$TEST_TMPDIR/apf.conf"
    printf 'IG_TCP_CPORTS="20,21,22,25,53,80,443,8080,8443"\n' > "$MOCK_CONF"

    # Prepare trust list destinations that must NOT be written
    MOCK_ALLOW="$TEST_TMPDIR/allow_hosts.rules"
    touch "$MOCK_ALLOW"

    # Cron dir for neutralize tests
    MOCK_CRON_DIR="$TEST_TMPDIR/cron.d"
    mkdir -p "$MOCK_CRON_DIR"
    printf '# mock\n0 * * * * root /usr/sbin/csf\n' > "$MOCK_CRON_DIR/csf_update"
    command chmod 644 "$MOCK_CRON_DIR/csf_update"
}

teardown() { csm_teardown; }

# ---------------------------------------------------------------------------
# csm_apply_var — dry-run gate
# ---------------------------------------------------------------------------

@test "dryrun: csm_apply_var does not modify target config file" {
    csm_apply_var "$MOCK_CONF" "IG_TCP_CPORTS" "1,2,3"
    # Original value must still be present
    grep -q '20,21,22' "$MOCK_CONF"
}

@test "dryrun: csm_apply_var adds WOULD SET report line" {
    _CSM_REPORT_LINES=()
    csm_apply_var "$MOCK_CONF" "IG_TCP_CPORTS" "1,2,3"
    local found=0
    local line
    for line in "${_CSM_REPORT_LINES[@]}"; do
        if [[ "$line" == "WOULD SET IG_TCP_CPORTS=1,2,3"* ]]; then
            found=1
            break
        fi
    done
    [ "$found" -eq 1 ]
}

# ---------------------------------------------------------------------------
# csm_apply_all — dry-run gate (uses norm store)
# ---------------------------------------------------------------------------

@test "dryrun: csm_apply_all leaves config file unchanged" {
    # Pre-populate norm store with one translated entry
    # shellcheck disable=SC2030
    _CSM_NORM_NAMES=("TCP_IN")
    _CSM_NORM_VALUES=("22,80,443")
    _CSM_NORM_STATUS=("translated")
    _CSM_NORM_TARGET=("IG_TCP_CPORTS")

    csm_apply_all "$MOCK_CONF"
    # File content must remain unchanged
    grep -q '20,21,22' "$MOCK_CONF"
}

# ---------------------------------------------------------------------------
# csm_migrate_trust_allow — dry-run gate
# ---------------------------------------------------------------------------

@test "dryrun: csm_migrate_trust_allow does not write to dst file" {
    local original_size
    original_size=$(wc -c < "$MOCK_ALLOW")
    csm_migrate_trust_allow "${PROJECT_ROOT}/tests/fixtures/csf/csf.allow" "$MOCK_ALLOW"
    local new_size
    new_size=$(wc -c < "$MOCK_ALLOW")
    [ "$original_size" -eq "$new_size" ]
}

# ---------------------------------------------------------------------------
# csm_neutralize — dry-run gate
# ---------------------------------------------------------------------------

@test "dryrun: csm_neutralize does not chmod cron file" {
    _CSM_REPORT_LINES=()
    _CSM_NEUTRALIZE_LOG=()
    csm_neutralize "csf" "$MOCK_CRON_DIR"
    # cron file must stay at 644
    local mode
    mode=$(stat -c '%a' "$MOCK_CRON_DIR/csf_update")
    [ "$mode" = "644" ]
}

@test "dryrun: csm_neutralize does not populate _CSM_NEUTRALIZE_LOG" {
    _CSM_NEUTRALIZE_LOG=()
    csm_neutralize "csf" "$MOCK_CRON_DIR"
    # Log must remain empty — no real chmod happened
    [ "${#_CSM_NEUTRALIZE_LOG[@]}" -eq 0 ]
}

# ---------------------------------------------------------------------------
# Translation arrays — still populated in dry-run
# ---------------------------------------------------------------------------

@test "dryrun: csm_translate_apf still populates norm store" {
    csm_translate_apf
    # Norm store must have entries regardless of dry-run
    # shellcheck disable=SC2031
    [ "${#_CSM_NORM_NAMES[@]}" -gt 0 ]
}

# ---------------------------------------------------------------------------
# Report still generated in dry-run
# ---------------------------------------------------------------------------

@test "dryrun: report buffer still populated" {
    _CSM_REPORT_LINES=()
    csm_apply_var "$MOCK_CONF" "IG_TCP_CPORTS" "1,2,3"
    [ "${#_CSM_REPORT_LINES[@]}" -gt 0 ]
}

@test "dryrun: WOULD prefix appears in report lines" {
    _CSM_REPORT_LINES=()
    csm_apply_var "$MOCK_CONF" "IG_TCP_CPORTS" "1,2,3"
    local found=0
    local line
    for line in "${_CSM_REPORT_LINES[@]}"; do
        if [[ "$line" == "WOULD"* ]]; then
            found=1
            break
        fi
    done
    [ "$found" -eq 1 ]
}

# ---------------------------------------------------------------------------
# csm_apply_var — write path (CSM_DRY_RUN=0)
# The write path delegates to pkg_config_set (fully tested in pkg_lib).
# This integration test verifies the delegation wiring is correct.
# ---------------------------------------------------------------------------

@test "write: csm_apply_var modifies target config file via pkg_config_set" {
    CSM_DRY_RUN="0"
    csm_apply_var "$MOCK_CONF" "IG_TCP_CPORTS" "1,2,3"
    grep -q 'IG_TCP_CPORTS="1,2,3"' "$MOCK_CONF"
}
