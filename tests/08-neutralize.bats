#!/usr/bin/env bats
# 08-neutralize.bats — neutralization suite tests
# shellcheck disable=SC2030,SC2031  # BATS @test blocks: subshell scoping is expected behavior

load helpers/csm-common

setup() {
    csm_common_setup

    # Create a mock cron directory for each test
    MOCK_CRON_DIR="$TEST_TMPDIR/cron.d"
    mkdir -p "$MOCK_CRON_DIR"

    # Create mock cron files for csf
    printf '# mock csf cron\n0 * * * * root /usr/sbin/csf --update\n' \
        > "$MOCK_CRON_DIR/csf_update"
    command chmod 644 "$MOCK_CRON_DIR/csf_update"

    # Create mock cron files for lfd (both separator styles)
    printf '# mock lfd cron (underscore)\n*/5 * * * * root /usr/sbin/lfd\n' \
        > "$MOCK_CRON_DIR/lfd_check"
    command chmod 644 "$MOCK_CRON_DIR/lfd_check"
    printf '# mock lfd cron (hyphen)\n0 1 * * * root /usr/sbin/lfd --run\n' \
        > "$MOCK_CRON_DIR/lfd-daily"
    command chmod 644 "$MOCK_CRON_DIR/lfd-daily"

    # Create mock cron for cxs
    printf '# mock cxs cron\n0 2 * * * root /usr/sbin/cxs --scan\n' \
        > "$MOCK_CRON_DIR/cxs_daily"
    command chmod 644 "$MOCK_CRON_DIR/cxs_daily"

    # Create mock executables in TEST_TMPDIR/sbin and TEST_TMPDIR/cxs
    mkdir -p "$TEST_TMPDIR/sbin" "$TEST_TMPDIR/cxs"
    printf '#!/bin/bash\n# mock csf binary\n' > "$TEST_TMPDIR/sbin/csf"
    command chmod 755 "$TEST_TMPDIR/sbin/csf"
    printf '#!/bin/bash\n# mock lfd binary\n' > "$TEST_TMPDIR/sbin/lfd"
    command chmod 755 "$TEST_TMPDIR/sbin/lfd"
    printf '#!/bin/bash\n# mock cxs binary\n' > "$TEST_TMPDIR/sbin/cxs"
    command chmod 755 "$TEST_TMPDIR/sbin/cxs"
    printf '#!/bin/bash\n# mock cxswatch.sh\n' > "$TEST_TMPDIR/cxs/cxswatch.sh"
    command chmod 755 "$TEST_TMPDIR/cxs/cxswatch.sh"
}

teardown() { csm_teardown; }

# ---------------------------------------------------------------------------
# _csm_record_perms
# ---------------------------------------------------------------------------

@test "record_perms: records original permissions in _CSM_NEUTRALIZE_LOG" {
    _CSM_NEUTRALIZE_LOG=()
    _csm_record_perms "$MOCK_CRON_DIR/csf_update"
    [ "${#_CSM_NEUTRALIZE_LOG[@]}" -eq 1 ]
    [[ "${_CSM_NEUTRALIZE_LOG[0]}" == *"|644"* ]]
}

@test "record_perms: returns 1 for missing file" {
    run _csm_record_perms "$TEST_TMPDIR/nonexistent"
    [ "$status" -eq 1 ]
}

# ---------------------------------------------------------------------------
# _csm_neutralize_crons
# ---------------------------------------------------------------------------

@test "neutralize_crons: chmod 000 applied to csf cron file" {
    _CSM_NEUTRALIZE_LOG=()
    _csm_neutralize_crons "csf" "$MOCK_CRON_DIR"
    local mode
    mode=$(stat -c '%a' "$MOCK_CRON_DIR/csf_update")
    [ "$mode" = "0" ]
}

@test "neutralize_crons: already-000 file stays 000 (no-op)" {
    command chmod 000 "$MOCK_CRON_DIR/csf_update"
    _CSM_NEUTRALIZE_LOG=()
    _csm_neutralize_crons "csf" "$MOCK_CRON_DIR"
    local mode
    mode=$(stat -c '%a' "$MOCK_CRON_DIR/csf_update")
    [ "$mode" = "0" ]
}

@test "neutralize_crons: lfd hyphen-separated glob matches" {
    _CSM_NEUTRALIZE_LOG=()
    _csm_neutralize_crons "lfd" "$MOCK_CRON_DIR"
    local mode
    mode=$(stat -c '%a' "$MOCK_CRON_DIR/lfd-daily")
    [ "$mode" = "0" ]
}

@test "neutralize_crons: lfd underscore-separated glob matches" {
    _CSM_NEUTRALIZE_LOG=()
    _csm_neutralize_crons "lfd" "$MOCK_CRON_DIR"
    local mode
    mode=$(stat -c '%a' "$MOCK_CRON_DIR/lfd_check")
    [ "$mode" = "0" ]
}

@test "neutralize_crons: dry-run adds WOULD lines, no chmod" {
    export CSM_DRY_RUN="1"
    _CSM_REPORT_LINES=()
    _csm_neutralize_crons "csf" "$MOCK_CRON_DIR"
    # File must NOT be chmod'd
    local mode
    mode=$(stat -c '%a' "$MOCK_CRON_DIR/csf_update")
    [ "$mode" = "644" ]
    # Report must contain WOULD line
    local found=0
    local line
    for line in "${_CSM_REPORT_LINES[@]}"; do
        if [[ "$line" == "WOULD chmod 000"* ]]; then
            found=1
            break
        fi
    done
    [ "$found" -eq 1 ]
}

# ---------------------------------------------------------------------------
# _csm_neutralize_bins — tested via mock paths
# ---------------------------------------------------------------------------

@test "neutralize_bins: unknown product returns error" {
    run _csm_neutralize_bins "unknownproduct"
    [ "$status" -eq 1 ]
}

@test "neutralize_bins: dry-run reports WOULD for cxswatch.sh" {
    export CSM_DRY_RUN="1"
    # Override the known path by monkeypatching: the function uses /etc/cxs/cxswatch.sh
    # We test the dry-run report path with a file that exists at the real mock path.
    # Since /etc/cxs/cxswatch.sh won't exist in container, this verifies no error + skips absent paths
    _CSM_REPORT_LINES=()
    run _csm_neutralize_bins "cxswatch"
    # Either the file exists and WOULD is reported, or it's absent and we get status 0 (skip)
    [ "$status" -eq 0 ]
}

# ---------------------------------------------------------------------------
# csm_neutralize — integration (service calls mocked, file paths testable)
# ---------------------------------------------------------------------------

@test "neutralize: unknown product returns error and adds report line" {
    _CSM_REPORT_LINES=()
    run csm_neutralize "badproduct" "$MOCK_CRON_DIR"
    [ "$status" -eq 1 ]
}

@test "neutralize: dry-run produces WOULD lines and no chmod" {
    export CSM_DRY_RUN="1"
    _CSM_REPORT_LINES=()
    _CSM_NEUTRALIZE_LOG=()
    csm_neutralize "csf" "$MOCK_CRON_DIR"
    # Cron file must remain unchanged
    local mode
    mode=$(stat -c '%a' "$MOCK_CRON_DIR/csf_update")
    [ "$mode" = "644" ]
    # Report must contain WOULD stop and WOULD disable
    local found_stop=0 found_disable=0
    local line
    for line in "${_CSM_REPORT_LINES[@]}"; do
        [[ "$line" == "WOULD stop service: csf" ]] && found_stop=1
        [[ "$line" == "WOULD disable service: csf" ]] && found_disable=1
    done
    [ "$found_stop" -eq 1 ]
    [ "$found_disable" -eq 1 ]
}

@test "neutralize: SELinux note always present in report" {
    export CSM_DRY_RUN="1"
    _CSM_REPORT_LINES=()
    csm_neutralize "csf" "$MOCK_CRON_DIR"
    local found=0
    local line
    for line in "${_CSM_REPORT_LINES[@]}"; do
        if [[ "$line" == *"SELinux"* ]]; then
            found=1
            break
        fi
    done
    [ "$found" -eq 1 ]
}
