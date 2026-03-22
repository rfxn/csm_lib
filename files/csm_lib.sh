#!/bin/bash
#
# csm_lib.sh — ConfigServer Migration Library 1.0.0
###
# Copyright (C) 2026 R-fx Networks <proj@rfxn.com>
#                     Ryan MacDonald <ryan@rfxn.com>
#
#    This program is free software; you can redistribute it and/or modify
#    it under the terms of the GNU General Public License as published by
#    the Free Software Foundation; either version 2 of the License, or
#    (at your option) any later version.
#
#    This program is distributed in the hope that it will be useful,
#    but WITHOUT ANY WARRANTY; without even the implied warranty of
#    MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.  See the
#    GNU General Public License for more details.
#
#    You should have received a copy of the GNU General Public License
#    along with this program; if not, write to the Free Software
#    Foundation, Inc., 59 Temple Place, Suite 330, Boston, MA  02111-1307  USA
###
#
# Shared ConfigServer migration library for rfxn projects.
# Source this file to access CSF/LFD/CXS detection, translation, and migration.
# No project-specific code — all behavior controlled via CSM_* variables.

# Source guard — safe for repeated sourcing
[[ -n "${_CSM_LIB_LOADED:-}" ]] && return 0 2>/dev/null  # suppresses "return outside function" when script is executed directly
_CSM_LIB_LOADED=1

# Hard require pkg_lib
if [[ -z "${_PKG_LIB_LOADED:-}" ]]; then
    echo "csm_lib: FATAL: pkg_lib must be sourced before csm_lib" >&2
    # shellcheck disable=SC2317  # exit 1 reachable when script is executed (not sourced)
    return 1 2>/dev/null || exit 1  # suppresses "return outside function" when executed directly
fi

# shellcheck disable=SC2034
CSM_LIB_VERSION="1.0.0"

# --- Configuration variables (set by consumer before sourcing) ---
CSM_CSF_CONF="${CSM_CSF_CONF:-/etc/csf/csf.conf}"
CSM_CSF_DIR="${CSM_CSF_DIR:-/etc/csf}"
CSM_CXS_DIR="${CSM_CXS_DIR:-/etc/cxs}"
CSM_CXS_DEFAULTS="${CSM_CXS_DEFAULTS:-/etc/cxs/cxs.defaults}"
CSM_CXS_WATCHCONF="${CSM_CXS_WATCHCONF:-/etc/cxs/cxswatch.conf}"
CSM_REPORT_FILE="${CSM_REPORT_FILE:-}"
CSM_DRY_RUN="${CSM_DRY_RUN:-0}"

# --- Internal state (parallel indexed arrays) ---
_CSM_RAW_NAMES=()
_CSM_RAW_VALUES=()
_CSM_NORM_NAMES=()
_CSM_NORM_VALUES=()
_CSM_NORM_STATUS=()
_CSM_NORM_TARGET=()
_CSM_BFD_RULES=()
_CSM_BFD_TRIPS=()
_CSM_REPORT_LINES=()
_CSM_NEUTRALIZE_LOG=()
_CSM_CXS_IGNORE_TYPES=()
_CSM_CXS_IGNORE_VALUES=()

# --- Detection state ---
_CSM_CSF_VERSION=""
_CSM_LFD_FOUND=0
_CSM_CXS_FOUND=0

# ---------------------------------------------------------------------------
# csm_reset — clear all state arrays for re-use across products
# ---------------------------------------------------------------------------
csm_reset() {
    _CSM_RAW_NAMES=()
    _CSM_RAW_VALUES=()
    _CSM_NORM_NAMES=()
    _CSM_NORM_VALUES=()
    _CSM_NORM_STATUS=()
    _CSM_NORM_TARGET=()
    _CSM_BFD_RULES=()
    _CSM_BFD_TRIPS=()
    _CSM_REPORT_LINES=()
    _CSM_NEUTRALIZE_LOG=()
    _CSM_CXS_IGNORE_TYPES=()
    _CSM_CXS_IGNORE_VALUES=()
    _CSM_CSF_VERSION=""
    _CSM_LFD_FOUND=0
    _CSM_CXS_FOUND=0
}
