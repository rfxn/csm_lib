#!/usr/bin/env bats
# 07-hooks.bats — hook script migration tests

load helpers/csm-common

setup() { csm_common_setup; }
teardown() { csm_teardown; }

# ---------------------------------------------------------------------------
# csm_migrate_hooks — copy, chmod 750, path rewrite
# ---------------------------------------------------------------------------

@test "hooks: csfpre.sh copied to hook_pre.sh" {
    csm_migrate_hooks "${PROJECT_ROOT}/tests/fixtures/csf" "$TEST_TMPDIR"
    [ -f "$TEST_TMPDIR/hook_pre.sh" ]
}

@test "hooks: csfpost.sh copied to hook_post.sh" {
    csm_migrate_hooks "${PROJECT_ROOT}/tests/fixtures/csf" "$TEST_TMPDIR"
    [ -f "$TEST_TMPDIR/hook_post.sh" ]
}

@test "hooks: hook_pre.sh has mode 750" {
    csm_migrate_hooks "${PROJECT_ROOT}/tests/fixtures/csf" "$TEST_TMPDIR"
    local mode
    mode=$(stat -c '%a' "$TEST_TMPDIR/hook_pre.sh")
    [ "$mode" = "750" ]
}

@test "hooks: hook_post.sh has mode 750" {
    csm_migrate_hooks "${PROJECT_ROOT}/tests/fixtures/csf" "$TEST_TMPDIR"
    local mode
    mode=$(stat -c '%a' "$TEST_TMPDIR/hook_post.sh")
    [ "$mode" = "750" ]
}

@test "hooks: /etc/csf/ paths rewritten to install_path in hook_pre.sh" {
    csm_migrate_hooks "${PROJECT_ROOT}/tests/fixtures/csf" "$TEST_TMPDIR"
    # Original csfpre.sh has: echo "pre-hook from /etc/csf/csfpre.sh"
    # After rewrite: /etc/csf/ → $TEST_TMPDIR/
    run grep "/etc/csf/" "$TEST_TMPDIR/hook_pre.sh"
    [ "$status" -ne 0 ]
    grep -q "$TEST_TMPDIR/" "$TEST_TMPDIR/hook_pre.sh"
}

@test "hooks: missing hook file handled gracefully (no error exit)" {
    # Remove csfpost.sh from fixture copy area — use a temp csf_dir with only pre
    local tmp_csf="$TEST_TMPDIR/csf_partial"
    mkdir -p "$tmp_csf"
    command cp "${PROJECT_ROOT}/tests/fixtures/csf/csfpre.sh" "$tmp_csf/"
    # csfpost.sh is absent
    run csm_migrate_hooks "$tmp_csf" "$TEST_TMPDIR"
    [ "$status" -eq 0 ]
    # pre hook should still be present
    [ -f "$TEST_TMPDIR/hook_pre.sh" ]
}

@test "hooks: report line generated with migrated count" {
    csm_migrate_hooks "${PROJECT_ROOT}/tests/fixtures/csf" "$TEST_TMPDIR"
    local found=0
    local line
    for line in "${_CSM_REPORT_LINES[@]}"; do
        if [[ "$line" == *"hooks migrated:"* ]]; then
            found=1
            break
        fi
    done
    [ "$found" -eq 1 ]
}
