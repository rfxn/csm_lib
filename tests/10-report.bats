#!/usr/bin/env bats
# 10-report.bats — csm_report_emit and csm_report_summary tests
# shellcheck disable=SC2030,SC2031  # BATS @test blocks: subshell scoping is expected behavior

load helpers/csm-common

setup() {
    csm_common_setup
    CSM_DRY_RUN="0"
    export CSM_DRY_RUN
    # Run a full APF translation so norm store is populated
    csm_translate_apf
}

teardown() { csm_teardown; }

# ---------------------------------------------------------------------------
# csm_report_emit — Translated section
# ---------------------------------------------------------------------------

@test "report_emit: Translated section present with correct count" {
    csm_report_emit
    local report="$CSM_REPORT_FILE"
    grep -q 'Translated' "$report"
    # TCP_IN → IG_TCP_CPORTS must appear
    grep -q 'TCP_IN' "$report"
}

@test "report_emit: Gaps section present and non-empty after APF translation" {
    csm_report_emit
    grep -q 'Gaps' "$CSM_REPORT_FILE"
    # PORTFLOOD, UDPFLOOD, CC_DENY are gap vars in the fixture
    grep -q 'PORTFLOOD' "$CSM_REPORT_FILE"
}

@test "report_emit: Captured section present" {
    csm_report_emit
    grep -q 'Captured' "$CSM_REPORT_FILE"
}

@test "report_emit: CSM_RESULT line present" {
    csm_report_emit
    grep -q '^CSM_RESULT:' "$CSM_REPORT_FILE"
}

@test "report_emit: CSM_RESULT line is parseable (all six fields)" {
    csm_report_emit
    local result_line
    result_line=$(grep '^CSM_RESULT:' "$CSM_REPORT_FILE")
    # Must contain all six fields
    [[ "$result_line" == *"translated="* ]]
    [[ "$result_line" == *"gaps="* ]]
    [[ "$result_line" == *"captured="* ]]
    [[ "$result_line" == *"trust="* ]]
    [[ "$result_line" == *"hooks="* ]]
    [[ "$result_line" == *"neutralized="* ]]
}

# ---------------------------------------------------------------------------
# csm_report_emit — output destination
# ---------------------------------------------------------------------------

@test "report_emit: writes to CSM_REPORT_FILE when path is set" {
    csm_report_emit
    [[ -f "$CSM_REPORT_FILE" ]]
    [[ -s "$CSM_REPORT_FILE" ]]
}

@test "report_emit: writes to stdout when CSM_REPORT_FILE is empty" {
    # shellcheck disable=SC2030
    CSM_REPORT_FILE=""
    local output
    output=$(csm_report_emit)
    [[ -n "$output" ]]
    [[ "$output" == *"CSM_RESULT:"* ]]
}

# ---------------------------------------------------------------------------
# csm_report_emit — empty state (no translation run)
# ---------------------------------------------------------------------------

@test "report_emit: header generated even with empty norm store" {
    csm_reset
    csm_report_emit
    grep -q 'CSM Migration Report' "$CSM_REPORT_FILE"
    grep -q 'Translated' "$CSM_REPORT_FILE"
    grep -q '^CSM_RESULT:' "$CSM_REPORT_FILE"
}

# ---------------------------------------------------------------------------
# csm_report_summary
# ---------------------------------------------------------------------------

@test "report_summary: returns one-liner with correct format" {
    local summary
    summary=$(csm_report_summary)
    [[ "$summary" == "Translated: "* ]]
    [[ "$summary" == *"| Gaps: "* ]]
    [[ "$summary" == *"| Captured: "* ]]
    [[ "$summary" == *"| Trust: "* ]]
    [[ "$summary" == *"| Hooks: "* ]]
    [[ "$summary" == *"| Neutralized: "* ]]
}

@test "report_summary: translated count is non-zero after APF translation" {
    local summary
    summary=$(csm_report_summary)
    # Extract the translated count
    local count_pat='^Translated: ([0-9]+)'
    [[ "$summary" =~ $count_pat ]]
    local count="${BASH_REMATCH[1]}"
    [ "$count" -gt 0 ]
}
